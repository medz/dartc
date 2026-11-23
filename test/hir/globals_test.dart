import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _n = HirField('n', .integer), _link = HirField('link', .reference);
final _class = HirClass('C', null, [_n, _link]);
final _inner = HirConstObject(_class, {_n: 5, _link: null});
final _outer = HirConstObject(_class, {_n: 6, _link: _inner});
final _count = HirGlobal('count', .integer, 3);
final _object = HirGlobal('object', .reference, _outer);
final _none = HirGlobal('none', .reference, null);
final _half = HirGlobal('half', .float, 0.5);

HirModule _module(
  HirTerminator Function(HirBlock block) build, {
  List<HirGlobal>? globals,
  List<HirClass>? classes,
  HirFunction? allocate,
}) {
  final module = body(build, [?allocate]);
  return HirModule(
    module.main,
    module.functions,
    classes: classes ?? [_class],
    globals: globals ?? [_count, _object, _none, _half],
    allocate: allocate,
  );
}

HirFunction _allocating(List<HirType> parameters, HirType? result) {
  final block = HirBlock(parameters);
  block.end(
    HirReturn(switch (result) {
      .integer => block.add(HirConst(0)),
      .float => block.add(HirConst(0.5)),
      _ => null,
    }),
  );
  return HirFunction('allocate', parameters, result)..define([block]);
}

void main() {
  group('interpreter', () {
    int? run(HirTerminator Function(HirBlock block) build) =>
        HirInterpreter(_module(build)).run();

    test('globals start with their values and keep new ones', () {
      final code = run((block) {
        final old = block.add(HirLoadGlobal(_count));
        final ten = block.add(HirConst(10));
        final next = block.add(HirIntBinary(.multiply, old, ten));
        block.add(HirStoreGlobal(_count, next));
        final again = block.add(HirLoadGlobal(_count));
        final none = block.add(HirLoadGlobal(_none));
        final isNull = block.add(
          HirCompare(.equal, none, block.add(HirNull())),
        );
        final half = block.add(HirLoadGlobal(_half));
        final isHalf = block.add(
          HirCompare(.equal, half, block.add(HirConst(0.5))),
        );
        final both = block.add(HirBoolBinary(.and, isNull, isHalf));
        final yes = HirBlock(), no = HirBlock();
        yes.end(HirExit(again));
        no.end(HirExit(no.add(HirConst(0))));
        return HirBranch(both, HirEdge(yes), HirEdge(no));
      });
      expect(code, 30);
    });

    test('constants are one object each', () {
      final code = run((block) {
        final global = block.add(HirLoadGlobal(_object));
        final outer = block.add(HirStatic(_outer));
        final same = block.add(HirCompare(.equal, global, outer));
        final link = block.add(HirLoad(_link, outer));
        final inner = block.add(HirStatic(_inner));
        final linked = block.add(HirCompare(.equal, link, inner));
        final differ = block.add(HirCompare(.notEqual, outer, inner));
        final both = block.add(HirBoolBinary(.and, same, linked));
        final all = block.add(HirBoolBinary(.and, both, differ));
        final yes = HirBlock(), no = HirBlock();
        final number = yes.add(HirLoad(_n, link));
        yes.end(HirExit(number));
        no.end(HirExit(no.add(HirConst(0))));
        return HirBranch(all, HirEdge(yes), HirEdge(no));
      });
      expect(code, 5);
    });

    test('constants cannot be changed', () {
      expect(
        () => run((block) {
          final object = block.add(HirStatic(_inner));
          block.add(HirStore(_n, object, block.add(HirConst(1))));
          return HirReturn();
        }),
        throwsStateError,
      );
    });

    test('machine operations are not interpreted', () {
      expect(
        () => run((block) {
          block.add(HirMachine(.classTable, []));
          return HirReturn();
        }),
        throwsStateError,
      );
    });
  });

  test('machine operations have the types of their functions', () {
    expect(HirMachine(.classTable, []).type, HirType.integer);
    expect(HirMachine(.collectsAlways, []).type, HirType.boolean);
    expect(HirMachine(.trap, []).type, isNull);
  });

  group('rejects', () {
    void rejects(String message, HirModule Function() build) =>
        test(message, () {
          expect(
            () => verifyHir(build()),
            throwsA(
              isA<HirError>().having(
                (e) => e.message,
                'message',
                contains(message),
              ),
            ),
          );
        });

    HirModule with_(HirInstruction Function(HirBlock block) build) =>
        _module((block) {
          block.add(build(block));
          return HirReturn();
        });

    rejects('a global is listed twice', () {
      return _module((_) => HirReturn(), globals: [_count, _count]);
    });
    rejects('unlisted global count', () {
      return _module((block) {
        block.add(HirLoadGlobal(_count));
        return HirReturn();
      }, globals: []);
    });
    rejects('unlisted global count', () {
      return _module((block) {
        block.add(HirStoreGlobal(_count, block.add(HirConst(1))));
        return HirReturn();
      }, globals: []);
    });
    rejects('global count: expected int', () {
      return with_((block) => HirStoreGlobal(_count, block.add(HirConst(0.5))));
    });
    for (final (type, value) in <(HirType, Object?)>[
      (.integer, 0.5),
      (.integer, null),
      (.float, 1),
      (.boolean, 1),
      (.reference, 1),
    ]) {
      rejects('global g starts with $value', () {
        return _module(
          (_) => HirReturn(),
          globals: [HirGlobal('g', type, value)],
        );
      });
    }
    rejects('unlisted class C', () {
      return _module((_) => HirReturn(), globals: [_object], classes: []);
    });
    rejects('unlisted class C', () {
      return _module(
        (block) {
          block.add(HirStatic(_inner));
          return HirReturn();
        },
        globals: [],
        classes: [],
      );
    });
    for (final fields in <Map<HirField, Object?>>[
      {_n: 1},
      {_n: 0.5, _link: null},
      {_n: 1, _link: 2},
      {_n: 1, _link: null, HirField('other', .integer): 2},
      {_n: 1, _link: HirConstObject(_class, {})},
    ]) {
      rejects('constant C has wrong fields', () {
        return with_((_) => HirStatic(HirConstObject(_class, fields)));
      });
    }
    rejects('store64: 1 for 2', () {
      return with_((block) => HirMachine(.store64, [block.add(HirConst(1))]));
    });
    rejects('load64: expected int', () {
      return with_((block) => HirMachine(.load64, [block.add(HirConst(0.5))]));
    });
    rejects('allocate is not listed', () {
      final module = body((_) => HirReturn());
      return HirModule(
        module.main,
        module.functions,
        allocate: _allocating([.integer], .integer),
      );
    });
    for (final (parameters, result) in <(List<HirType>, HirType?)>[
      ([], .integer),
      ([.float], .integer),
      ([.integer], null),
      ([.integer], .float),
    ]) {
      rejects('allocate has another signature', () {
        return _module(
          (_) => HirReturn(),
          allocate: _allocating(parameters, result),
        );
      });
    }
  });

  test('accepts a function to allocate with', () {
    verifyHir(
      _module((_) => HirReturn(), allocate: _allocating([.integer], .integer)),
    );
  });

  test('prints', () {
    final module = _module((block) {
      final one = block.add(HirLoadGlobal(_count));
      block
        ..add(HirStoreGlobal(_count, one))
        ..add(HirStatic(_outer))
        ..add(HirMachine(.store64, [one, one]));
      return HirReturn();
    });
    expect(printHir(module), '''
class C { int n; reference link; }
global int count = 3
global reference object = C(6, C(5, null))
global reference none = null
global double half = 0.5
void main {
b0():
  v0 = count
  count = v0
  v1 = const C(6, C(5, null))
  store64(v0, v0)
  return
}''');
  });
}
