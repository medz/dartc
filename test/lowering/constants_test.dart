import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/constants.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async => fixture = FixtureComparison(
      await CheckedLibraries.read([
        'test/lowering/fixtures/constants.dart',
        'test/lowering/fixtures/constants_private.dart',
      ], Lowering.lower),
    ),
  );

  test('reads of a named constant share its IR operand', () {
    final function = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'collectionOrder',
    );
    final maps = function.blocks
        .expand((block) => block.instructions)
        .expand((instruction) => instruction.inputs)
        .whereType<MapConstant>()
        .toList();
    expect(maps.length, greaterThan(1));
    expect(maps.skip(1), everyElement(same(maps.first)));
  });

  for (final (name, reference) in <(String, Object? Function())>[
    ('rootObjectIdentity', sdk.rootObjectIdentity),
    ('importedConstructorAlias', sdk.importedConstructorAlias),
    ('collectionTypes', sdk.collectionTypes),
    ('collectionOrder', sdk.collectionOrder),
    ('collectionEmptyNested', sdk.collectionEmptyNested),
    ('collectionControl', sdk.collectionControl),
    ('objectFields', sdk.objectFields),
    ('canonicalObjects', sdk.canonicalObjects),
    ('redirectedAndDefaults', sdk.redirectedAndDefaults),
    ('equalityVersusIdentity', sdk.equalityVersusIdentity),
    ('canonicalCollections', sdk.canonicalCollections),
    ('widenedRecordCanonicalization', sdk.widenedRecordCanonicalization),
    ('orderedCanonicalCollections', sdk.orderedCanonicalCollections),
    ('listReadBounds', sdk.listReadBounds),
  ]) {
    test('$name matches the SDK', () => fixture.compare(name, [], reference));
  }
  test(
    'constant patterns invoke user equality rather than canonical identity',
    () {
      for (final value in [0, 1, 2, 3, 4]) {
        fixture.compare('constantEqualityPattern', [
          value,
        ], () => sdk.constantEqualityPattern(value));
      }
    },
  );
  test('constant object patterns dispatch overridden getters in order', () {
    for (final derived in [false, true]) {
      fixture.compare('constantPatterns', [
        derived,
      ], () => sdk.constantPatterns(derived));
    }
  });
  test(
    'function aliases remain callable inside constant objects and lists',
    () {
      for (final value in [-1, 0, 7]) {
        fixture.compare('embeddedFunctions', [
          value,
        ], () => sdk.embeddedFunctions(value));
      }
    },
  );
  test('alias constructor tearoffs survive nested constants and defaults', () {
    for (final value in [-1, 0, 7]) {
      fixture.compare('embeddedAliasConstructors', [
        value,
      ], () => sdk.embeddedAliasConstructors(value));
    }
  });
  test('method addAll checks the source reified type before reading it', () {
    for (final kind in [0, 1, 2]) {
      for (final immutable in [false, true]) {
        for (final custom in [false, true]) {
          fixture.compare('addAllSourceType', [
            kind,
            immutable,
            custom,
          ], () => sdk.addAllSourceType(kind, immutable, custom));
        }
      }
    }
  });
  test('literal spreads check dynamic elements in iteration order', () {
    for (final fail in [false, true]) {
      for (final asSet in [false, true]) {
        fixture.compare('literalDynamicSpread', [
          fail,
          asSet,
        ], () => sdk.literalDynamicSpread(fail, asSet));
      }
    }
  });
  for (final (name, reference, count) in <(String, int Function(int), int)>[
    ('listMutation', sdk.listMutation, 6),
    ('setMutation', sdk.setMutation, 4),
    ('mapMutation', sdk.mapMutation, 4),
  ]) {
    for (var operation = 0; operation < count; operation++) {
      final selected = operation;
      test(
        '$name operation $selected matches SDK exception and source effects',
        () {
          fixture.compare(name, [selected], () => reference(selected));
        },
      );
    }
  }
}
