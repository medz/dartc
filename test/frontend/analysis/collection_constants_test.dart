import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  const directory = 'test/frontend/analysis/fixtures/collections/';
  late LoweringResult result;
  setUpAll(() async {
    result = await AnalysisSession(['${directory}valid.dart'])
        .use(Lowering().lower);
  });
  for (final (name, expected) in [
    ('listSum', 57),
    ('mapSum', 10),
    ('setSum', 9),
    ('sizes', 6),
  ]) {
    test('$name retains evaluated collection contents', () {
      final runner = IrInterpreter(result.program, {});
      final function = result.program.functions.singleWhere(
        (f) => f.target.name == name,
      );
      expect(runner.run(function, []), expected, reason: name);
    });
  }

  for (final fixture in [
    'duplicate_map',
    'duplicate_set',
    'list_type',
    'set_type',
    'map_type',
    'map_value',
    'primitive',
    'nonconstant_branch',
    'nonconstant_literal',
    'static_list_branch',
    'static_list_type',
    'static_set_type',
    'static_map_key',
    'static_map_value',
    'static_list_spread',
    'static_map_spread',
    'static_null_aware',
  ]) {
    test('checks $fixture before allowing consumption', () async {
      await expectLater(
        AnalysisSession(['$directory$fixture.dart'])
            .use((_) => fail('An invalid collection passed analysis.')),
        throwsFormatException,
      );
    });
  }
}
