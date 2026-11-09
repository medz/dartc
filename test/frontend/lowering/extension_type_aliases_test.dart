import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/extension_type_aliases.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_type_aliases');
  });
  test('erased constructor aliases retain mappings and callable identity', () {
    fixture.compare('construction', [], sdk.construction);
    fixture.compare('identity', [], sdk.identity);
    fixture.compare('constantCalls', [], sdk.constantCalls);
    for (final mode in [0, 1, 2, 3]) {
      fixture.compare('dynamicCall', [mode], () => sdk.dynamicCall(mode));
    }
  });
  test(
    'contextual alias instantiation preserves the selected arguments',
    () async {
      final fixture = await FixtureComparison.load('extension_alias_inference');
      final run = fixture.program.functions.singleWhere(
        (f) => f.target.name == 'inferred',
      );
      expect(IrInterpreter(fixture.program, {}).run(run, []), '7:eight');
    },
  );
}
