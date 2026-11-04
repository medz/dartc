import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/object_patterns.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('object_patterns');
  });

  test(
    'object fields preserve source order, dispatch, guards and exceptions',
    () {
      for (final seed in [-12, -1, 0, 1, 4]) {
        for (final derived in [false, true]) {
          fixture.compare('orderedObject', [
            seed,
            derived,
          ], () => sdk.orderedObject(seed, derived));
          fixture.compare('typeAlternativeObject', [
            seed,
            derived,
          ], () => sdk.typeAlternativeObject(seed, derived));
        }
        for (final (name, function) in <(String, int Function(int))>[
          ('shortObject', sdk.shortObject),
          ('wildcardObject', sdk.wildcardObject),
          ('nullableObject', sdk.nullableObject),
          ('assertObject', sdk.assertObject),
          ('declareObject', sdk.declareObject),
          ('assignObject', sdk.assignObject),
          ('methodObject', sdk.methodObject),
          ('nestedObject', sdk.nestedObject),
          ('alternativeObject', sdk.alternativeObject),
          ('andObject', sdk.andObject),
          ('nestedAlternativeObject', sdk.nestedAlternativeObject),
          ('switchObject', sdk.switchObject),
          ('switchStatementObject', sdk.switchStatementObject),
          ('castObject', sdk.castObject),
          ('nestedGetterObject', sdk.nestedGetterObject),
          ('loopObject', sdk.loopObject),
          ('guardedMutationObject', sdk.guardedMutationObject),
          ('narrowedGetterObject', sdk.narrowedGetterObject),
          ('separateMatchesObject', sdk.separateMatchesObject),
          ('relationalAndObject', sdk.relationalAndObject),
          ('relationalOrObject', sdk.relationalOrObject),
          ('equalityComplementObject', sdk.equalityComplementObject),
          ('distinctRelationalObject', sdk.distinctRelationalObject),
          ('guardedRelationalObject', sdk.guardedRelationalObject),
          ('canonicalRelationalObject', sdk.canonicalRelationalObject),
          ('relationalStatementObject', sdk.relationalStatementObject),
          ('recordEqualityObject', sdk.recordEqualityObject),
          ('distinctEqualityObject', sdk.distinctEqualityObject),
          ('nanEqualityObject', sdk.nanEqualityObject),
          ('receiverPathsObject', sdk.receiverPathsObject),
        ]) {
          fixture.compare(name, [seed], () => function(seed));
        }
      }
    },
  );

  test(
    'type misses do not access getters and builtin empty patterns match',
    () {
      for (final value in <Object?>[null, 42, 'hello', true, 1.5]) {
        fixture.compare('mismatchObject', [
          value,
        ], () => sdk.mismatchObject(value));
      }
    },
  );
}
