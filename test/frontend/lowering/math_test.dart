import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession(['test/compiler/fixtures/math.dart'])
        .use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {});
    functions = {
      for (final function in program.functions)
        if (function.target.owner == null) function.target.name: function,
    };
  });

  test(
    'SDK identity survives aliases without intercepting user declarations',
    () {
      for (final name in [
        'squareRoot',
        'integerRoot',
        'numberRoot',
        'dynamicRoot',
      ]) {
        final operations = functions[name]!.blocks.expand(
          (b) => b.instructions,
        );
        expect(operations.whereType<NumericSquareRoot>(), hasLength(1));
      }
      expect(
        functions['sqrt']!.blocks
            .expand((b) => b.instructions)
            .whereType<NumericSquareRoot>(),
        isEmpty,
      );
      expect(runner.run(functions['shadowed']!, [9.0]), 128.0);
    },
  );

  test(
    'num and dynamic inputs retain conversion and checked-call semantics',
    () {
      for (final name in ['numberRoot', 'dynamicRoot']) {
        for (final value in <num>[9, 9.0]) {
          expect(runner.run(functions[name]!, [value]), 3.0);
        }
        expect(runner.run(functions[name]!, [-1]), isNaN);
        final zero = runner.run(functions[name]!, [-0.0]) as double;
        expect(zero, 0);
        expect(zero.isNegative, isTrue);
      }
      for (final value in [null, true, '9']) {
        expect(
          () => runner.run(functions['dynamicRoot']!, [value]),
          throwsA(isA<TypeError>()),
        );
      }
    },
  );
}
