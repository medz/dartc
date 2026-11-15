import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/loop_calls.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/loop_calls.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });

  test('finite known callbacks are discardable despite allocation failure', () {
    final function = program.functions.singleWhere(
      (body) => body.target.name == 'nestedCallbacks',
    );
    final facts = ProgramFlow(program, [
      (target: function.target, arguments: [FlowValue.unknown(.integer)]),
    ], allocationFailure: heapRuntime.allocationFailure).facts;
    final call = function.blocks
        .expand((block) => block.instructions)
        .whereType<DirectCall>()
        .single;
    expect(facts.canDiscard(call), isTrue);
    expect(facts.exitsOf(call), (normal: true, exceptional: true));
  });

  for (final (name, evaluate) in <(String, int Function(int))>[
    ('factoryLoop', source.factoryLoop),
    ('retainedIterations', source.retainedIterations),
    ('retainedCallerAlias', source.retainedCallerAlias),
    ('previousIteration', source.previousIteration),
    ('preservedCaller', source.preservedCaller),
    ('chainSum', source.chainSum),
    ('recursiveStored', source.recursiveStored),
    ('pairedFactories', source.pairedFactories),
    ('nestedCallbacks', source.nestedCallbacks),
    ('recursiveCallback', source.recursiveCallback),
    ('nestedThrow', source.nestedThrow),
  ]) {
    test('source execution retains $name for runtime input', () {
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
            ProgramBranchSpecialization(),
          ]).run(program, [
            (target: function.target, arguments: [FlowValue.unknown(.integer)]),
          ], allocationFailure: heapRuntime.allocationFailure);
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
      if (name == 'nestedCallbacks' || name == 'nestedThrow') {
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
