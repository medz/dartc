import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _x = HirField('x', .integer), _next = HirField('next', .reference);
final _y = HirField('y', .float);
final _base = HirClass('Base', null, [_x, _next]);
final _derived = HirClass('Derived', _base, [_y]);
final _other = HirClass('Other', null, []);
final _get = HirSelector('get', [.integer], .integer);

/// A method returning [amount] plus its argument.
HirFunction _method(String name, int amount) {
  final block = HirBlock([.reference, .integer]);
  final constant = block.add(HirConst(amount));
  block.end(
    HirReturn(block.add(HirIntBinary(.add, block.parameters[1], constant))),
  );
  return HirFunction(name, [.reference, .integer], .integer)..define([block]);
}

final _baseGet = _method('Base.get', 10), _derivedGet = _method('D.get', 20);

HirModule _module(
  HirTerminator Function(HirBlock block) build, {
  List<HirClass>? classes,
  Map<HirSelector, Map<HirClass, HirFunction>>? dispatch,
}) {
  final module = body(build, [_baseGet, _derivedGet]);
  return HirModule(
    module.main,
    module.functions,
    classes: classes ?? [_base, _derived, _other],
    dispatch:
        dispatch ??
        {
          _get: {_base: _baseGet, _derived: _derivedGet},
        },
  );
}

void main() {
  test('a class has its superclass fields first', () {
    expect(_derived.fields, [_x, _next, _y]);
    expect(_derived.isSubclassOf(_base), isTrue);
    expect(_base.isSubclassOf(_base), isTrue);
    expect(_base.isSubclassOf(_derived), isFalse);
    expect(_other.isSubclassOf(_base), isFalse);
  });

  group('interpreter', () {
    int? run(HirTerminator Function(HirBlock block) build) =>
        HirInterpreter(_module(build)).run();

    test('fields keep their values for each object', () {
      final code = run((block) {
        final a = block.add(HirNew(_derived)), b = block.add(HirNew(_base));
        final two = block.add(HirConst(2)), three = block.add(HirConst(3));
        block
          ..add(HirStore(_x, a, two))
          ..add(HirStore(_x, b, three))
          ..add(HirStore(_next, a, b));
        final link = block.add(HirLoad(_next, a));
        final left = block.add(HirLoad(_x, link));
        final right = block.add(HirLoad(_x, a));
        final ten = block.add(HirConst(10));
        final scaled = block.add(HirIntBinary(.multiply, left, ten));
        return HirExit(block.add(HirIntBinary(.add, scaled, right)));
      });
      expect(code, 32);
    });

    test('calls depend on the class of the object', () {
      final code = run((block) {
        final one = block.add(HirConst(1));
        final a = block.add(HirNew(_base)), b = block.add(HirNew(_derived));
        final first = block.add(HirVirtualCall(_get, a, [one]));
        final second = block.add(HirVirtualCall(_get, b, [first]));
        return HirExit(second);
      });
      expect(code, 31);
    });

    test('references are compared by identity', () {
      for (final (same, expected) in [(true, 1), (false, 0)]) {
        final code = run((block) {
          final a = block.add(HirNew(_base)), b = block.add(HirNew(_base));
          final none = block.add(HirNull());
          final found = block.add(HirCompare(.equal, a, same ? a : b));
          final fresh = block.add(HirLoad(_next, a));
          final isNull = block.add(HirCompare(.equal, fresh, none));
          final differs = block.add(HirCompare(.notEqual, a, none));
          final both = block.add(HirBoolBinary(.and, isNull, differs));
          final all = block.add(HirBoolBinary(.and, found, both));
          final yes = HirBlock(), no = HirBlock();
          yes.end(HirExit(yes.add(HirConst(1))));
          no.end(HirExit(no.add(HirConst(0))));
          return HirBranch(all, HirEdge(yes), HirEdge(no));
        });
        expect(code, expected);
      }
    });

    test('broken programs are errors', () {
      final errors = <HirTerminator Function(HirBlock block)>[
        // A number read before it is stored.
        (block) => HirExit(block.add(HirLoad(_x, block.add(HirNew(_base))))),
        // A field of another class.
        (block) {
          block.add(HirLoad(_next, block.add(HirNew(_other))));
          return HirReturn();
        },
        (block) {
          final object = block.add(HirNew(_other));
          block.add(HirStore(_next, object, object));
          return HirReturn();
        },
        // Null.
        (block) {
          block.add(HirLoad(_next, block.add(HirNull())));
          return HirReturn();
        },
        (block) {
          final none = block.add(HirNull());
          block.add(HirStore(_next, none, none));
          return HirReturn();
        },
        (block) {
          final none = block.add(HirNull()), one = block.add(HirConst(1));
          return HirExit(block.add(HirVirtualCall(_get, none, [one])));
        },
        // No implementation.
        (block) {
          final one = block.add(HirConst(1));
          final object = block.add(HirNew(_other));
          return HirExit(block.add(HirVirtualCall(_get, object, [one])));
        },
      ];
      for (final build in errors) {
        expect(() => run(build), throwsStateError);
      }
    });
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

    HirModule with_(void Function(HirBlock block, HirValue object) build) =>
        _module((block) {
          build(block, block.add(HirNew(_base)));
          return HirReturn();
        });

    rejects('a class is listed twice', () {
      return _module((_) => HirReturn(), classes: [_base, _base]);
    });
    rejects('unlisted class Other', () {
      return _module((block) {
        block.add(HirNew(_other));
        return HirReturn();
      }, classes: [_base, _derived]);
    });
    rejects('Base is no box', () {
      return with_((block, _) {
        block.add(HirBox(_base, block.add(HirConst(1))));
      });
    });
    rejects('object: expected reference', () {
      return with_(
        (block, _) => block.add(HirUnbox(_x, block.add(HirConst(1)))),
      );
    });
    rejects('object: expected reference', () {
      return with_(
        (block, _) => block.add(HirLoad(_x, block.add(HirConst(1)))),
      );
    });
    rejects('object: expected reference', () {
      return with_((block, _) {
        final one = block.add(HirConst(1));
        block.add(HirStore(_x, one, one));
      });
    });
    rejects('field x: expected int', () {
      return with_((block, object) => block.add(HirStore(_x, object, object)));
    });
    rejects('receiver: expected reference', () {
      return with_((block, _) {
        final one = block.add(HirConst(1));
        block.add(HirVirtualCall(_get, one, [one]));
      });
    });
    rejects('call to get: 0 for 1', () {
      return with_((block, object) {
        block.add(HirVirtualCall(_get, object, []));
      });
    });
    rejects('call to get: expected int', () {
      return with_((block, object) {
        block.add(HirVirtualCall(_get, object, [object]));
      });
    });
    rejects('unlisted selector get', () {
      return _module((block) {
        final object = block.add(HirNew(_base)), one = block.add(HirConst(1));
        block.add(HirVirtualCall(_get, object, [one]));
        return HirReturn();
      }, dispatch: {});
    });
    rejects('get: unlisted class Other', () {
      return _module(
        (_) => HirReturn(),
        classes: [_base],
        dispatch: {
          _get: {_other: _baseGet},
        },
      );
    });
    rejects('get: unlisted function', () {
      return _module(
        (_) => HirReturn(),
        dispatch: {
          _get: {_base: _method('elsewhere', 1)},
        },
      );
    });
    for (final (parameters, result) in <(List<HirType>, HirType?)>[
      ([], .integer),
      ([.float], .integer),
      ([.integer], null),
      ([.integer], .float),
    ]) {
      rejects('get: Base.get has another signature', () {
        return _module(
          (_) => HirReturn(),
          dispatch: {
            HirSelector('get', parameters, result): {_base: _baseGet},
          },
        );
      });
    }
    rejects('reference has no <', () {
      return with_((block, object) {
        block.add(HirCompare(.less, object, object));
      });
    });
  });

  test('prints objects', () {
    final module = _module((block) {
      final object = block.add(HirNew(_base)), none = block.add(HirNull());
      block.add(HirStore(_next, object, none));
      final one = block.add(HirConst(1));
      block
        ..add(HirLoad(_next, object))
        ..add(HirVirtualCall(_get, object, [one]));
      return HirReturn();
    });
    expect(
      printHir(module),
      contains('''
  v0 = new Base
  v1 = null
  v0.next = v1
  v2 = 1
  v3 = v0.next
  v4 = v0->get(v2)
'''),
    );
    expect(
      printHir(module),
      startsWith('''
class Base { int x; reference next; }
class Derived extends Base { double y; }
class Other { }
dispatch get: Base => Base.get, Derived => D.get
'''),
    );
  });
}
