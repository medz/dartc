import 'package:test/test.dart';
import 'package:dartc/ir.dart';

import 'fixture_comparison.dart';
import 'fixtures/promoted_intersections.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async =>
        fixture = await FixtureComparison.load('promoted_intersections'),
  );
  for (final (name, expected) in [
    ('numericCases', sdk.numericCases),
    ('listCases', sdk.listCases),
    ('recordCases', sdk.recordCases),
    ('functionCases', sdk.functionCases),
    ('nullableCases', sdk.nullableCases),
    ('objectCases', sdk.objectCases),
    ('captureCases', sdk.captureCases),
    ('boundedCases', sdk.boundedCases),
    ('futureCases', sdk.futureCases),
    ('revokedCases', sdk.revokedCases),
    ('nestedCases', sdk.nestedCases),
    ('genericFunctionCases', sdk.genericFunctionCases),
    ('fieldCases', sdk.fieldCases),
    ('nullableRecordCases', sdk.nullableRecordCases),
    ('nullableFunctionCases', sdk.nullableFunctionCases),
    ('nonNullReturnCases', sdk.nonNullReturnCases),
    ('otherParameterCases', sdk.otherParameterCases),
    ('boundedRecordCases', sdk.boundedRecordCases),
    ('boundedFunctionCases', sdk.boundedFunctionCases),
    ('originalRecordCases', sdk.originalRecordCases),
    ('originalFunctionCases', sdk.originalFunctionCases),
    ('originalGenericFunctionCases', sdk.originalGenericFunctionCases),
    (
      'genericPromotionSubstitutionCases',
      sdk.genericPromotionSubstitutionCases,
    ),
    (
      'capturedPromotionSubstitutionCases',
      sdk.capturedPromotionSubstitutionCases,
    ),
  ]) {
    test('$name matches SDK', () => fixture.compare(name, [], expected));
  }
  test('original structural views do not need another runtime cast', () {
    for (final name in [
      'originalRecordBound',
      'originalFunctionBound',
      'originalGenericFunctionBound',
    ]) {
      final function = fixture.program.functions.singleWhere(
        (f) => f.target.name == name,
      );
      expect(
        function.blocks.expand((b) => b.instructions).whereType<TypeCast>(),
        isEmpty,
        reason: name,
      );
    }
  });
}
