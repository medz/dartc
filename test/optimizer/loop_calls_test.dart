import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/loop_calls.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession(['test/optimizer/fixtures/loop_calls.dart'])
        .use((input) async => (await Lowering().lower(input)).program);
  });

  for (final (name, evaluate) in <(String, int Function(int))>[
    ('factoryLoop', source.factoryLoop),
    ('previousIteration', source.previousIteration),
    ('preservedCaller', source.preservedCaller),
    ('chainSum', source.chainSum),
    ('recursiveStored', source.recursiveStored),
  ]) {
    test('source loop retains $name for runtime input', () {
      final function = program.functions.singleWhere(
        (body) => body.target.name == name,
      );
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ]).run(program, [
            (target: function.target, arguments: [FlowValue.unknown(.integer)]),
          ]);
      expect(facts.returnedBy(function.target).isBottom, isFalse);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final count in [-2, 0, 1, 4, 9]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [count]),
          evaluate(count),
          reason: '$name($count)',
        );
      }
    });
  }
}
