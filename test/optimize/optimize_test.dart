import 'package:dartc/hir.dart';
import 'package:dartc/optimize.dart';
import 'package:test/test.dart';

final _x = HirField('x', .integer);
final _fixed = HirField('fixed', .integer, isFinal: true);
final _a = HirClass('A', null, [_x, _fixed]);
final _b = HirClass('B', _a, const []);
final _c = HirClass('C', _a, const []);
final _isA = HirTypeTest('A'), _isB = HirTypeTest('B');
final _get = HirSelector('get', const [], .integer);

HirFunction _function(
  String name,
  List<HirType> parameters,
  HirType? result,
  HirValue? Function(HirBlock block, List<HirValue> parameters) build,
) {
  final block = HirBlock(parameters);
  block.end(HirReturn(build(block, block.parameters)));
  return HirFunction(name, parameters, result)..define([block]);
}

HirModule _module(
  HirFunction main, {
  List<HirFunction> others = const [],
  Map<HirSelector, Map<HirClass, HirFunction>> dispatch = const {},
  Map<HirSelector, List<HirClass>> likely = const {},
}) => HirModule(
  main,
  [main, ...others],
  classes: [_a, _b, _c],
  dispatch: dispatch,
  likely: likely,
  tests: {
    _isA: {_a, _b, _c},
    _isB: {_b},
  },
);

/// A program that exits with what [build] gives.
HirFunction _exiting(HirValue Function(HirBlock block) build) {
  final block = HirBlock();
  block.end(HirExit(build(block)));
  return HirFunction('main', const [])..define([block]);
}

HirModule _optimized(HirModule module, int? expected) {
  expect(HirInterpreter(module).run(), expected);
  final result = optimizeProgram(module);
  verifyHir(result);
  expect(HirInterpreter(result).run(), expected);
  return result;
}

String _main(HirModule module) {
  final text = printHir(module);
  final start = text.indexOf(' main {');
  return text.substring(start, text.indexOf('\n}', start));
}

void main() {
  test('nothing changes without optimizations', () {
    final module = _module(_exiting((block) => block.add(HirConst(3))));
    expect(optimizeProgram(module, enabled: const {}), same(module));
  });

  test('constants are folded', () {
    final module = _module(
      _exiting((block) {
        final two = block.add(HirConst(2)), three = block.add(HirConst(3));
        final six = block.add(HirIntBinary(.multiply, two, three));
        return block.add(HirIntBinary(.subtract, six, two));
      }),
    );
    final text = _main(_optimized(module, 4));
    expect(text, contains('= 4\n'));
    expect(text, isNot(contains('*')));
  });

  test('impossible operations are not done early', () {
    final entry = HirBlock(), never = HirBlock(), done = HirBlock();
    final zero = entry.add(HirConst(0)), no = entry.add(HirConst(false));
    entry.end(HirBranch(no, HirEdge(never), HirEdge(done)));
    never.end(HirExit(never.add(HirIntBinary(.divide, zero, zero))));
    done.end(HirExit(done.add(HirConst(5))));
    final main = HirFunction('main', const [])..define([entry, never, done]);
    _optimized(_module(main), 5);
  });

  test('branches on what is known are gone, also after joins', () {
    final get = _function('input', const [], .boolean, (block, _) {
      final value = block.add(HirMachine(.steadyTime, const []));
      final zero = block.add(HirConst(-1));
      return block.add(HirCompare(.greater, value, zero));
    });
    final entry = HirBlock(), left = HirBlock(), right = HirBlock();
    final join = HirBlock(const [.boolean]);
    final yes = HirBlock(), no = HirBlock();
    final condition = entry.add(HirCall(get, const []));
    entry.end(HirBranch(condition, HirEdge(left), HirEdge(right)));
    left.end(HirJump(HirEdge(join, [left.add(HirConst(true))])));
    right.end(HirJump(HirEdge(join, [right.add(HirConst(false))])));
    join.end(HirBranch(join.parameters.single, HirEdge(yes), HirEdge(no)));
    yes.end(HirExit(yes.add(HirConst(1))));
    no.end(HirExit(no.add(HirConst(2))));
    final main = HirFunction('main', const [])
      ..define([entry, left, right, join, yes, no]);
    final text = _main(_optimized(_module(main, others: [get]), 1));
    expect('branch'.allMatches(text), hasLength(1));
    expect(text, isNot(contains('(v')));
  });

  group('objects', () {
    test('that nothing sees are gone', () {
      final module = _module(
        _exiting((block) {
          final object = block.add(HirNew(_a));
          block.add(HirStore(_x, object, block.add(HirConst(3))));
          return block.add(HirLoad(_x, object));
        }),
      );
      expect(_main(_optimized(module, 3)), isNot(contains('new')));
    });

    test('that others see are kept', () {
      final read = _function('read', [.reference], .integer, (block, p) {
        final time = block.add(HirMachine(.steadyTime, const []));
        final zero = block.add(HirConst(0));
        final none = block.add(HirIntBinary(.and, time, zero));
        final value = block.add(HirLoad(_x, p.single));
        return block.add(HirIntBinary(.add, value, none));
      });
      final module = _module(
        _exiting((block) {
          final object = block.add(HirNew(_a));
          block.add(HirStore(_x, object, block.add(HirConst(3))));
          return block.add(HirCall(read, [object]));
        }),
        others: [read],
      );
      _optimized(module, 3);
    });

    test('fields may change through other names and calls', () {
      final change = _function('change', [.reference], null, (block, p) {
        block.add(HirStore(_x, p.single, block.add(HirConst(9))));
        // It is not small.
        for (var i = 0; i < 20; i++) {
          block.add(HirMachine(.steadyTime, const []));
        }
        return null;
      });
      final main = _exiting((block) {
        final object = block.add(HirNew(_a));
        block.add(HirStore(_x, object, block.add(HirConst(3))));
        block.add(HirStore(_fixed, object, block.add(HirConst(50))));
        final before = block.add(HirLoad(_x, object));
        block.add(HirCall(change, [object]));
        final after = block.add(HirLoad(_x, object));
        final fixed = block.add(HirLoad(_fixed, object));
        final sum = block.add(HirIntBinary(.add, before, after));
        return block.add(HirIntBinary(.add, sum, fixed));
      });
      final text = _main(_optimized(_module(main, others: [change]), 62));
      expect(text, contains('.x\n'));
      expect(text, isNot(contains('.fixed\n')));
    });

    test('boxes and what is in them are the same', () {
      final value = HirField('value', .integer);
      final box = HirClass('Box', null, [value]);
      final main = _exiting((block) {
        final boxed = block.add(HirBox(box, block.add(HirConst(7))));
        final again = block.add(HirBox(box, block.add(HirUnbox(value, boxed))));
        return block.add(HirUnbox(value, again));
      });
      final module = HirModule(main, [main], classes: [box], integers: box);
      expect(_main(_optimized(module, 7)), isNot(contains('Box')));
    });

    test('boxes are not taken for those of other values', () {
      final number = HirField('value', .integer);
      final numbers = HirClass('Number', null, [number]);
      final fraction = HirField('value', .float);
      final fractions = HirClass('Fraction', null, [fraction]);
      final start = HirBlock(), never = HirBlock(), end = HirBlock();
      final boxed = start.add(HirBox(fractions, start.add(HirConst(1.5))));
      final time = start.add(HirMachine(.steadyTime, const []));
      final isEarly = start.add(
        HirCompare(.less, time, start.add(HirConst(0))),
      );
      start.end(HirBranch(isEarly, HirEdge(never), HirEdge(end)));
      // The time tells the same as the class does elsewhere.
      final value = never.add(HirUnbox(number, boxed));
      final sum = never.add(HirIntBinary(.add, value, never.add(HirConst(1))));
      never.end(HirExit(sum));
      end.end(HirExit(end.add(HirConst(5))));
      final main = HirFunction('main', const [])..define([start, never, end]);
      final module = HirModule(main, [main], classes: [numbers, fractions]);
      _optimized(module, 5);
    });
  });

  group('calls', () {
    final two = _function('two', [.reference], .integer, (block, _) {
      return block.add(HirConst(2));
    });
    final own = _function('own', [.reference], .integer, (block, p) {
      return block.add(HirLoad(_x, p.single));
    });

    HirFunction calling(HirClass class_, {HirTypeTest? bound}) => _exiting((
      block,
    ) {
      final object = block.add(HirNew(class_));
      block.add(HirStore(_x, object, block.add(HirConst(40))));
      return block.add(HirVirtualCall(_get, object, const [], bound: bound));
    });

    test('of known classes are replaced by what is called', () {
      for (final (class_, expected) in [(_a, 40), (_b, 2), (_c, 40)]) {
        final module = _module(
          calling(class_),
          others: [two, own],
          dispatch: {
            _get: {_a: own, _b: two, _c: own},
          },
        );
        final result = _optimized(module, expected);
        expect(result.functions, [result.main]);
        expect(result.dispatch, isEmpty);
      }
    });

    /// A program that gets objects of [classes] from a list.
    HirModule choosing(
      List<HirClass> classes, {
      HirTypeTest? bound,
      List<HirClass> likely = const [],
    }) {
      final array = HirClass('Array', null, const [], .references);
      final length = classes.length;
      final main = _exiting((block) {
        final list = block.add(HirNewArray(array, block.add(HirConst(length))));
        for (final (i, class_) in classes.indexed) {
          final object = block.add(HirNew(class_));
          block.add(HirStore(_x, object, block.add(HirConst(10 * i + 10))));
          final index = block.add(HirConst(i));
          block.add(HirStoreElement(.reference, list, index, object));
        }
        HirValue sum = block.add(HirConst(0));
        for (var i = 0; i < length; i++) {
          final index = block.add(HirConst(i));
          final object = block.add(HirLoadElement(.reference, list, index));
          final got = block.add(
            HirVirtualCall(_get, object, const [], bound: bound),
          );
          sum = block.add(HirIntBinary(.add, sum, got));
        }
        return sum;
      });
      return HirModule(
        main,
        [main, two, own],
        classes: [array, _a, _b, _c],
        tests: {
          _isA: {_a, _b, _c},
          _isB: {_b},
        },
        dispatch: {
          _get: {_a: own, _b: two, _c: own},
        },
        likely: {_get: likely},
      );
    }

    test('of few classes ask for the class', () {
      final module = choosing([_a, _b, _c, _b], bound: _isA);
      final text = _main(_optimized(module, 44));
      expect(text, contains('is exactly'));
      expect(text, isNot(contains('->')));
    });

    test('of likely classes ask for those first', () {
      final module = choosing([_a, _b, _c], likely: [_b]);
      final text = _main(_optimized(module, 42));
      expect(text, contains('is exactly B'));
      expect(text, contains('->get'));
    });

    test('are not replaced if that is not wanted', () {
      final module = choosing([_a, _b], bound: _isA);
      final text = _main(optimizeProgram(module, enabled: {.inline}));
      expect(text, contains('->get'));
      expect(text, isNot(contains('is exactly')));
    });

    test('that throw are caught where they were', () {
      final divide = () {
        final block = HirBlock(const [.integer, .integer]);
        final bad = HirBlock(), good = HirBlock();
        final [a, b] = block.parameters;
        final isZero = block.add(HirCompare(.equal, b, block.add(HirConst(0))));
        block.end(HirBranch(isZero, HirEdge(bad), HirEdge(good)));
        final object = bad.add(HirNew(_a));
        bad.add(HirStore(_x, object, a));
        bad.end(HirThrow(object, bad.add(HirNew(_c))));
        good.end(HirReturn(good.add(HirIntBinary(.divide, a, b))));
        return HirFunction('divide', const [.integer, .integer], .integer)
          ..define([block, bad, good]);
      }();
      for (final (divisor, expected) in [(0, 70), (5, 14)]) {
        final entry = HirBlock(), normal = HirBlock(const [.integer]);
        final caught = HirBlock(const [.reference, .reference, .integer]);
        final time = entry.add(HirMachine(.steadyTime, const []));
        final zero = entry.add(
          HirIntBinary(.and, time, entry.add(HirConst(0))),
        );
        final by = entry.add(
          HirIntBinary(.add, zero, entry.add(HirConst(divisor))),
        );
        final seventy = entry.add(HirConst(70));
        entry.end(
          HirInvoke(
            HirCall(divide, [seventy, by]),
            HirEdge(normal),
            HirEdge(caught, [by]),
          ),
        );
        normal.end(HirExit(normal.parameters.single));
        final x = caught.add(HirLoad(_x, caught.parameters[0]));
        caught.end(
          HirExit(caught.add(HirIntBinary(.add, x, caught.parameters[2]))),
        );
        final main = HirFunction('main', const [])
          ..define([entry, normal, caught]);
        final result = _optimized(_module(main, others: [divide]), expected);
        expect(result.functions, [result.main]);
      }
    });

    test('of functions that call themselves are kept', () {
      final fall = HirFunction('fall', const [.integer], .integer);
      final block = HirBlock(const [.integer]);
      final more = HirBlock(), end = HirBlock();
      final n = block.parameters.single;
      final isEnd = block.add(HirCompare(.less, n, block.add(HirConst(1))));
      block.end(HirBranch(isEnd, HirEdge(end), HirEdge(more)));
      end.end(HirReturn(n));
      final less = more.add(HirIntBinary(.subtract, n, more.add(HirConst(1))));
      more.end(HirReturn(more.add(HirCall(fall, [less]))));
      fall.define([block, more, end]);
      final main = _exiting(
        (block) => block.add(HirCall(fall, [block.add(HirConst(30))])),
      );
      _optimized(_module(main, others: [fall]), 0);
    });
  });
}
