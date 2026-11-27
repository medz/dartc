import 'package:dartc/hir.dart';
import 'package:test/test.dart';

import 'support.dart';

final _value = HirField('value', .integer);
final _integers = HirClass('Integer', null, [_value]);
final _a = HirClass('A', null, const []), _b = HirClass('B', null, const []);
final _kind = HirField('kind', .integer);
final _types = HirClass('Type', null, [_kind]);
final _isInteger = HirTypeTest('integer'), _isA = HirTypeTest('A');
final _integerType = HirConstObject(_types, {_kind: 1});
final _aType = HirConstObject(_types, {_kind: 2});
final _otherType = HirConstObject(_types, {_kind: 3});

/// What stands for the runtime: it ends the program with 9, so that the
/// program tells whether it was asked.
final HirFunction _isInstance = () {
  final block = HirBlock([.reference, .reference]);
  block.end(HirExit(block.add(HirConst(9))));
  return HirFunction('isInstance', const [.reference, .reference], .boolean)
    ..define([block]);
}();

/// Exits with 1 if `isInstance` of its arguments is true, or with 0.
final HirFunction _check = () {
  final entry = HirBlock([.reference, .reference]);
  final yes = HirBlock(), no = HirBlock();
  final [object, type] = entry.parameters;
  final isOf = entry.add(HirCall(_isInstance, [object, type]));
  entry.end(HirBranch(isOf, HirEdge(yes), HirEdge(no)));
  yes.end(HirExit(yes.add(HirConst(1))));
  no.end(HirExit(no.add(HirConst(0))));
  return HirFunction('check', const [.reference, .reference])
    ..define([entry, yes, no]);
}();

/// A program that tests the object that [object] makes against [type], which
/// it gives as it is if [isKnown] and through a call if not.
HirModule _testing(
  HirValue Function(HirBlock block) object,
  HirConstObject type, {
  bool isKnown = false,
  bool hasSealed = true,
}) {
  final entry = HirBlock(), blocks = [entry];
  final value = object(entry), given = entry.add(HirStatic(type));
  if (isKnown) {
    final yes = HirBlock(), no = HirBlock();
    final isOf = entry.add(HirCall(_isInstance, [value, given]));
    entry.end(HirBranch(isOf, HirEdge(yes), HirEdge(no)));
    yes.end(HirExit(yes.add(HirConst(1))));
    no.end(HirExit(no.add(HirConst(0))));
    blocks.addAll([yes, no]);
  } else {
    entry
      ..add(HirCall(_check, [value, given]))
      ..end(HirReturn());
  }
  final main = HirFunction('main', const [])..define(blocks);
  return HirModule(
    main,
    [main, _check, _isInstance],
    classes: [_integers, _a, _b, _types],
    tests: {
      _isInteger: {_integers},
      _isA: {_a},
    },
    integers: _integers,
    isInstance: _isInstance,
    sealedTypes: hasSealed ? {_integerType: _isInteger, _aType: _isA} : {},
  );
}

HirValue _newA(HirBlock block) => block.add(HirNew(_a));
HirValue _newB(HirBlock block) => block.add(HirNew(_b));
HirValue _null(HirBlock block) => block.add(HirNull());
HirValue Function(HirBlock) _integer(int value) =>
    (block) => block.add(HirBox(_integers, block.add(HirConst(value))));

void main() {
  group('lowering decides by class', () {
    for (final isKnown in [false, true]) {
      final how = isKnown ? 'a known type' : 'a type that is given';
      test('that objects are of $how', () {
        expect(runLowered(_testing(_newA, _aType, isKnown: isKnown)), 1);
        for (final value in [0, 5, -1, 1 << 62, -1 << 63]) {
          final module = _testing(
            _integer(value),
            _integerType,
            isKnown: isKnown,
          );
          expect(runLowered(module), 1, reason: '$value');
        }
      });

      test('and asks the runtime about the rest, for $how', () {
        expect(runLowered(_testing(_newB, _aType, isKnown: isKnown)), 9);
        expect(runLowered(_testing(_null, _aType, isKnown: isKnown)), 9);
        expect(runLowered(_testing(_integer(5), _aType, isKnown: isKnown)), 9);
        expect(runLowered(_testing(_newA, _otherType, isKnown: isKnown)), 9);
      });
    }

    test('only for the types it is told', () {
      expect(runLowered(_testing(_newA, _aType, hasSealed: false)), 9);
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

    HirModule withRuntime(
      HirFunction isInstance,
      Map<HirTypeTest, Set<HirClass>> tests,
    ) {
      final main = HirFunction('main', const [])
        ..define([HirBlock()..end(HirReturn())]);
      return HirModule(
        main,
        [main, isInstance],
        classes: [_a, _types],
        tests: tests,
        isInstance: isInstance,
        sealedTypes: {_aType: _isA},
      );
    }

    test('no module that is right', () {
      verifyHir(_testing(_newA, _aType));
      verifyHir(
        withRuntime(_isInstance, {
          _isA: {_a},
        }),
      );
    });
    rejects('isInstance has another signature', () {
      final block = HirBlock([.reference])..end(HirReturn());
      return withRuntime(
        HirFunction('isInstance', const [.reference])..define([block]),
        {
          _isA: {_a},
        },
      );
    });
    rejects('sealed type: unlisted test A', () => withRuntime(_isInstance, {}));
    rejects('sealed types without isInstance', () {
      final main = HirFunction('main', const [])
        ..define([HirBlock()..end(HirReturn())]);
      return HirModule(
        main,
        [main],
        classes: [_a, _types],
        tests: {
          _isA: {_a},
        },
        sealedTypes: {_aType: _isA},
      );
    });
  });
}
