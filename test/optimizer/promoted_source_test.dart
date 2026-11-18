import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/promoted_types.dart' as source;

void main() {
  late IrProgram program;
  late Map<String, FunctionTarget> roots;
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/promoted_types.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
    roots = {
      for (final function in program.functions)
        if (function.target.library?.path.endsWith(
                  '/fixtures/promoted_types.dart',
                ) ==
                true &&
            const {
              'objectArgument',
              'integerArgument',
              'observesObjectArgument',
              'observesIntegerArgument',
            }.contains(function.target.name))
          function.target.name: function.target,
    };
  });

  test(
    'source generic promotions preserve reified arguments and record fields',
    () {
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
      final runner = IrInterpreter(facts.program, {});
      Object? run(String name, Object? argument) => runner.run(
        facts.program.implementationOf(roots[name]!) as IrFunction,
        [argument],
      );

      expect(source.objectArgument(42), 30);
      expect(source.integerArgument(42), 31);
      for (final value in <Object?>[-7, 0, 42, 1.25, 'other', null]) {
        expect(run('objectArgument', value), source.objectArgument(value));
        expect(
          run('observesObjectArgument', value),
          source.observesObjectArgument(value),
        );
        if (value is int) {
          expect(run('integerArgument', value), source.integerArgument(value));
          expect(
            run('observesIntegerArgument', value),
            source.observesIntegerArgument(value),
          );
        }
      }
    },
  );
}
