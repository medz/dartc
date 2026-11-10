import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/runtime_type.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async => fixture = await FixtureComparison.load('runtime_type'));

  for (final (name, expected) in [
    ('staticRuntimeTypes', sdk.staticRuntimeTypes),
    ('shapedRuntimeTypes', sdk.shapedRuntimeTypes),
    ('overriddenRuntimeType', sdk.overriddenRuntimeType),
    ('runtimeTypeWildcard', sdk.runtimeTypeWildcard),
    ('pointerRuntimeTypes', sdk.pointerRuntimeTypes),
  ]) {
    test('$name matches the Dart SDK', () {
      fixture.compare(name, [], expected);
    });
  }

  test('object patterns share cached runtimeType getter results', () {
    for (final overridden in [false, true]) {
      fixture.compare('runtimeTypePattern', [
        overridden,
      ], () => sdk.runtimeTypePattern(overridden));
    }
  });

  for (final name in ['setRuntimeType', 'mapRuntimeType', 'errorRuntimeType']) {
    test('$name retains the unsupported concrete SDK type boundary', () {
      final entry = fixture.program.functions.singleWhere(
        (function) => function.target.name == name,
      );
      expect(
        () => IrInterpreter(fixture.program, {}).run(entry, []),
        throwsUnsupportedError,
      );
    });
  }

  test('super.runtimeType uses the selected ancestor, not an override', () {
    fixture.compare('superRuntimeType', [], sdk.superRuntimeType);
    final actual = fixture.program.functions.singleWhere(
      (function) => function.target.name == 'actual',
    );
    final reads = actual.blocks
        .expand((block) => block.instructions)
        .whereType<ObjectRuntimeType>();
    expect(reads.single.direct, isTrue);
  });
}
