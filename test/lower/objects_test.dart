import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

final _x = HirField('x', .integer), _next = HirField('next', .reference);
final _y = HirField('y', .float), _z = HirField('z', .boolean);
final _base = HirClass('Base', null, [_x, _next]);
final _left = HirClass('Left', _base, [_y]);
final _right = HirClass('Right', _base, [_z]);
final _get = HirSelector('get', [.integer], .integer);
final _other = HirSelector('other', [.float, .reference], .float);

HirFunction _method(String name, int amount) {
  final block = HirBlock([.reference, .integer]);
  final own = block.add(HirLoad(_x, block.parameters[0]));
  final sum = block.add(HirIntBinary(.add, own, block.parameters[1]));
  final constant = block.add(HirConst(amount));
  block.end(HirReturn(block.add(HirIntBinary(.add, sum, constant))));
  return HirFunction(name, [.reference, .integer], .integer)..define([block]);
}

HirModule _module(HirTerminator Function(HirBlock block) build) {
  final twice = HirBlock([.reference, .float, .reference]);
  final value = twice.parameters[1];
  twice.end(HirReturn(twice.add(HirFloatBinary(.add, value, value))));
  final methods = [
    _method('Base.get', 100),
    _method('Left.get', 200),
    HirFunction('twice', [.reference, .float, .reference], .float)
      ..define([twice]),
  ];
  final module = body(build, methods);
  return HirModule(
    module.main,
    module.functions,
    classes: [_base, _left, _right],
    dispatch: {
      _get: {_base: methods[0], _left: methods[1], _right: methods[0]},
      _other: {_right: methods[2]},
    },
  );
}

void main() {
  test('eight tests of classes share a table', () {
    final classes = [
      for (var i = 0; i < 5; i++) HirClass('C$i', null, const []),
    ];
    // No other test is passed by the same classes, so none can take its place.
    final tests = <HirTypeTest, Set<HirClass>>{
      for (var i = 0; i < 20; i++)
        HirTypeTest('t$i'): {
          for (final (j, class_) in classes.indexed)
            if (i >> j & 1 != 0) class_,
        },
    };
    final entry = HirBlock(), wrong = HirBlock();
    var block = entry;
    for (final MapEntry(key: test, value: passing) in tests.entries) {
      for (final class_ in classes) {
        final object = block.add(HirNew(class_)), next = HirBlock();
        final passes = block.add(HirIsInstance(test, object));
        final isRight = passing.contains(class_);
        block.end(
          HirBranch(
            passes,
            HirEdge(isRight ? next : wrong),
            HirEdge(isRight ? wrong : next),
          ),
        );
        block = next;
      }
    }
    block.end(HirExit(block.add(HirConst(7))));
    wrong.end(HirExit(wrong.add(HirConst(1))));
    final blocks = reversePostorder(
      entry,
      (block) => block.terminator!.edges.map((edge) => edge.target),
    );
    final main = HirFunction('main', const [])..define(blocks);
    final module = HirModule(main, [main], classes: classes, tests: tests);
    expect(HirInterpreter(module).run(), 7);
    expect(runLowered(module), 7);
    final tables = lowerProgram(module).data
        .where((data) => data.bytes.length == classes.length);
    expect(tables, hasLength(3));
  });

  /// Runs at both levels, which must agree.
  int? run(HirTerminator Function(HirBlock block) build) {
    final module = _module(build);
    final code = HirInterpreter(module).run();
    expect(runLowered(module), code);
    return code;
  }

  test('fields of every type, inherited and own', () {
    final code = run((block) {
      final a = block.add(HirNew(_left)), b = block.add(HirNew(_right));
      final five = block.add(HirConst(5)), half = block.add(HirConst(0.5));
      final yes = block.add(HirConst(true));
      block
        ..add(HirStore(_x, a, five))
        ..add(HirStore(_y, a, half))
        ..add(HirStore(_next, a, b))
        ..add(HirStore(_z, b, yes))
        ..add(HirStore(_x, b, block.add(HirConst(7))));
      final link = block.add(HirLoad(_next, a));
      final same = block.add(HirCompare(.equal, link, b));
      final none = block.add(HirLoad(_next, b));
      final isNull = block.add(HirCompare(.equal, none, block.add(HirNull())));
      final float = block.add(
        HirCompare(.equal, block.add(HirLoad(_y, a)), half),
      );
      var all = block.add(HirLoad(_z, link)) as HirValue;
      for (final part in [same, isNull, float]) {
        all = block.add(HirBoolBinary(.and, all, part));
      }
      final left = block.add(HirLoad(_x, a)), right = block.add(HirLoad(_x, b));
      final yesBlock = HirBlock(), noBlock = HirBlock();
      yesBlock.end(HirExit(yesBlock.add(HirIntBinary(.multiply, left, right))));
      noBlock.end(HirExit(noBlock.add(HirConst(0))));
      return HirBranch(all, HirEdge(yesBlock), HirEdge(noBlock));
    });
    expect(code, 35);
  });

  test('calls find the function of each class', () {
    for (final (class_, expected) in [
      (_base, 113),
      (_left, 213),
      (_right, 113),
    ]) {
      final code = run((block) {
        final object = block.add(HirNew(class_));
        block.add(HirStore(_x, object, block.add(HirConst(3))));
        final ten = block.add(HirConst(10));
        return HirExit(block.add(HirVirtualCall(_get, object, [ten])));
      });
      expect(code, expected, reason: class_.name);
    }
  });

  test('selectors of other signatures stay apart', () {
    final code = run((block) {
      final object = block.add(HirNew(_right));
      final value = block.add(HirConst(1.25));
      final result = block.add(HirVirtualCall(_other, object, [value, object]));
      final right = block.add(HirConst(2.5));
      final same = block.add(HirCompare(.equal, result, right));
      final yes = HirBlock(), no = HirBlock();
      yes.end(HirExit(yes.add(HirConst(1))));
      no.end(HirExit(no.add(HirConst(0))));
      return HirBranch(same, HirEdge(yes), HirEdge(no));
    });
    expect(code, 1);
  });

  test('a selector nothing implements lowers to a call never made', () {
    final unused = HirSelector('unused', [], .integer);
    final module = body((block) {
      final none = block.add(HirNull());
      final yes = HirBlock(), no = HirBlock();
      yes.end(HirExit(yes.add(HirVirtualCall(unused, none, []))));
      no.end(HirExit(no.add(HirConst(4))));
      final isNull = block.add(
        HirCompare(.notEqual, none, block.add(HirNull())),
      );
      return HirBranch(isNull, HirEdge(yes), HirEdge(no));
    });
    final code = runLowered(
      HirModule(module.main, module.functions, dispatch: {unused: {}}),
    );
    expect(code, 4);
  });

  test('a program without virtual calls needs no table', () {
    expect(lowerProgram(body((_) => HirReturn())).tables, isEmpty);
  });
}
