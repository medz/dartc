import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/invocation_forms.dart' as sdk;

void main() {
  test(
    'ordinary and shorthand calls retain generic checks and effect order',
    () async {
      const path = 'test/frontend/lowering/fixtures/invocation_forms.dart';
      final program = await AnalysisSession([path])
          .use((input) => Lowering().lower(input).program);
      final function = program.functions.singleWhere(
        (f) => f.target.name == 'forms',
      );
      final runner = IrInterpreter(program, {
        (
          Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
          'tick',
        ): effects.tick,
      });
      (Object?, List<int>) observe(Object? Function() run) {
        effects.calls.clear();
        Object? result;
        try {
          result = run();
        } on TypeError {
          result = TypeError;
        }
        return (result, List.of(effects.calls));
      }

      for (final value in [7, 'bad', null]) {
        for (var form = 0; form < 6; form++) {
          final expected = observe(() => sdk.forms(value, form));
          final actual = observe(() => runner.run(function, [value, form]));
          expect(actual.$1, expected.$1, reason: 'form $form, value $value');
          expect(actual.$2, expected.$2, reason: 'form $form, value $value');
        }
      }
    },
  );
}
