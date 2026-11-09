import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/dynamic_values.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('dynamic_values');
  });

  for (final (name, function, inputs)
      in <(String, int Function(dynamic), List<Object?>)>[
        ('contextualRecord', sdk.contextualRecord, [2, 'bad', null, true, 1.5]),
        (
          'parameterAssignment',
          sdk.parameterAssignment,
          [2, 'bad', null, true, 1.5],
        ),
        (
          'capturedAssignment',
          sdk.capturedAssignment,
          [2, 'bad', null, true, 1.5],
        ),
        (
          'constructorArgument',
          sdk.constructorArgument,
          [2, 'bad', null, true, 1.5],
        ),
        ('staticArgument', sdk.staticArgument, [2, 'bad', null, true, 1.5]),
        ('functionArgument', sdk.functionArgument, [2, 'bad', null, true, 1.5]),
        ('intOperator', sdk.intOperator, [2, 'bad', null, true, 1.5]),
        ('stringOperator', sdk.stringOperator, [2, 'bad', null, true, 1.5]),
        ('userOperator', sdk.userOperator, [2, 'bad', null, true, 1.5]),
        ('neverReturn', sdk.neverReturn, [2, 'bad', null, true, 1.5]),
        ('neverArgument', sdk.neverArgument, [2, 'bad', null, true, 1.5]),
        ('neverElement', sdk.neverElement, [2, 'bad', null, true, 1.5]),
        ('genericBoundTypes', sdk.genericBoundTypes, [0, 1, 2]),
        ('genericAliasEquality', sdk.genericAliasEquality, [0]),
        ('localCast', sdk.localCast, [2, 'bad', null, true, 1.5]),
        ('assignmentCast', sdk.assignmentCast, [2, 'bad', null, true, 1.5]),
        ('returnCast', sdk.returnCast, [2, 'bad', null, true, 1.5]),
        ('typedReturn', sdk.typedReturn, [2, 'bad', null, true, 1.5]),
        ('argumentCast', sdk.argumentCast, [2, 'bad', null, true, 1.5]),
        ('setterCast', sdk.setterCast, [2, 'bad', null, true, 1.5]),
        ('fieldCast', sdk.fieldCast, [2, 'bad', null, true, 1.5]),
        ('indexKeyCast', sdk.indexKeyCast, [2, 'bad', null, true, 1.5]),
        ('indexValueCast', sdk.indexValueCast, [2, 'bad', null, true, 1.5]),
        ('listElementCast', sdk.listElementCast, [2, 'bad', null, true, 1.5]),
        ('mapKeyCast', sdk.mapKeyCast, [2, 'bad', null, true, 1.5]),
        ('mapValueCast', sdk.mapValueCast, [2, 'bad', null, true, 1.5]),
        ('genericCast', sdk.genericCast, [2, 'bad', null, true, 1.5]),
        ('dynamicStorage', sdk.dynamicStorage, [2, 'bad', null, true, 1.5]),
        (
          'conditionAndRight',
          sdk.conditionAndRight,
          [true, false, 2, 'bad', null],
        ),
        (
          'conditionOrRight',
          sdk.conditionOrRight,
          [true, false, 2, 'bad', null],
        ),
        (
          'conditionAndSkipped',
          sdk.conditionAndSkipped,
          [true, false, 2, 'bad', null],
        ),
        (
          'conditionOrSkipped',
          sdk.conditionOrSkipped,
          [true, false, 2, 'bad', null],
        ),
        ('conditionIf', sdk.conditionIf, [true, false, 2, 'bad', null]),
        ('conditionWhile', sdk.conditionWhile, [true, false, 2, 'bad', null]),
        ('conditionFor', sdk.conditionFor, [true, false, 2, 'bad', null]),
        ('conditionDo', sdk.conditionDo, [true, false, 2, 'bad', null]),
        (
          'conditionTernary',
          sdk.conditionTernary,
          [true, false, 2, 'bad', null],
        ),
        ('conditionAnd', sdk.conditionAnd, [true, false, 2, 'bad', null]),
        ('conditionOr', sdk.conditionOr, [true, false, 2, 'bad', null]),
        ('conditionNot', sdk.conditionNot, [true, false, 2, 'bad', null]),
      ]) {
    test('$name matches SDK implicit casts and effect order', () {
      for (final input in inputs) {
        fixture.compare(name, [input], () => function(input));
      }
    });
  }
}
