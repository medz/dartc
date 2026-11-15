import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  test('constructor effects survive after objects and discarded unwind traces disappear', () async {
    await prepareRuntime('test/compiler/fixtures/constructor_effects.dart');
    final program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
    final roots = {
      for (final name in ['construct', 'count'])
        name: program.functions
            .singleWhere(
              (f) =>
                  f.target.name == name &&
                  f.target.library?.path.endsWith(
                        '/constructor_effects.dart',
                      ) ==
                      true,
            )
            .target,
    };
    final facts =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramCallSpecialization(),
          ProgramStoragePromotion(),
          ProgramStorageElimination(),
          DirectCallInlining(),
        ]).run(
          program,
          [],
          openEntries: roots.values,
          allocationFailure: heapRuntime.allocationFailure,
        );
    final body =
        facts.program.implementationOf(roots['construct']!) as IrFunction;
    final count = facts.program.implementationOf(roots['count']!) as IrFunction;
    final runner = IrInterpreter(facts.program, {});
    var visits = 0;
    for (final value in [-7, 0, 42]) {
      for (final fail in [false, true]) {
        visits++;
        expect(runner.run(body, [value, fail]), fail ? -visits : value);
        expect(runner.run(count, []), visits);
      }
    }
    expect(body.blocks.map((b) => b.end).whereType<Throw>(), isEmpty);
    expect(
      facts.program.functions
          .where((function) => facts.definitions.contains(function.target))
          .expand((function) => function.blocks)
          .expand(
            (block) => [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ],
          )
          .where(
            (operation) =>
                facts.effectsOf(operation).contains(Effect.allocates),
          ),
      isEmpty,
    );
  });
}
