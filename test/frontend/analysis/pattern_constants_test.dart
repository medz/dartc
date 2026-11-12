import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  const directory = 'test/frontend/analysis/fixtures/patterns/';
  late LoweringResult result;
  setUpAll(() async {
    result = await AnalysisSession(['${directory}valid.dart'])
        .use(Lowering().lower);
  });

  test(
    'keeps the exhaustiveness rules of the library language version',
    () async {
      final result = await AnalysisSession(['${directory}legacy_switch.dart'])
          .use(Lowering().lower);
      final function = result.program.functions.singleWhere(
        (f) => f.target.name == 'legacy',
      );
      final runner = IrInterpreter(result.program, {});
      expect(runner.run(function, [true]), 1);
      expect(runner.run(function, [false]), 2);
    },
  );

  for (final (name, arguments, expected) in <(String, List<Object?>, int)>[
    ('boolean', [true], 1),
    ('boolean', [false], 2),
    ('nullable', [null], 0),
    ('nullable', [true], 1),
    ('nullable', [false], 2),
    ('pair', [true, false], 1),
    ('pair', [false, true], 2),
    ('pair', [false, false], 3),
    ('statement', [true], 1),
    ('statement', [false], 2),
    ('returning', [true], 1),
    ('returning', [false], 2),
    ('sealed', [true, true], 1),
    ('sealed', [true, false], 2),
    ('sealed', [false, false], 3),
    ('keys', [], 7),
    ('enumeration', [true], 1),
    ('enumeration', [false], 2),
    ('enumRecord', [true, false], 1),
    ('enumRecord', [false, true], 2),
    ('enumRecord', [false, false], 3),
    ('genericEnum', [], 7),
  ]) {
    test('$name $arguments uses the checked pattern values', () {
      final function = result.program.functions.singleWhere(
        (f) => f.target.name == name && f.target.owner == null,
      );
      expect(
        IrInterpreter(result.program, {}).run(function, arguments),
        expected,
      );
    });
  }

  for (final fixture in [
    'nonexhaustive',
    'duplicate_keys',
    'guarded',
    'unrelated_error',
    'nested',
    'promotion',
  ]) {
    test('rejects $fixture before allowing consumption', () async {
      await expectLater(
        AnalysisSession(['$directory$fixture.dart'])
            .use((_) => fail('An invalid pattern passed analysis.')),
        throwsFormatException,
      );
    });
  }
}
