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

  test('finite known callbacks have no recursion or execution obligation', () {
    final function = program.functions.singleWhere(
      (body) => body.target.name == 'nestedCallbacks',
    );
    final facts = ProgramFlow(program, [
      (target: function.target, arguments: [FlowValue.unknown(.integer)]),
    ]).facts;
    final call = function.blocks
        .expand((block) => block.instructions)
        .whereType<DirectCall>()
        .single;
    expect(facts.canDiscard(call), isTrue);
    expect(facts.exitsOf(call), (normal: true, exceptional: false));
  });

  for (final (name, evaluate) in <(String, int Function(int))>[
    ('factoryLoop', source.factoryLoop),
    ('previousIteration', source.previousIteration),
    ('preservedCaller', source.preservedCaller),
    ('chainSum', source.chainSum),
    ('recursiveStored', source.recursiveStored),
    ('pairedFactories', source.pairedFactories),
    ('nestedCallbacks', source.nestedCallbacks),
    ('recursiveCallback', source.recursiveCallback),
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
      if (name == 'nestedCallbacks') {
        expect(
          rewritten.blocks
              .expand(
                (block) => [
                  ...block.instructions,
                  if (block.end case Invoke(:final operation)) operation,
                ],
              )
              .where(
                (operation) =>
                    operation is FunctionCall ||
                    operation is DirectCall ||
                    operation is MakeClosure,
              ),
          isEmpty,
        );
      }
    });
  }
}
