import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/zone_state.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/zone_state.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  for (final (name, evaluate) in [
    ('zoneCall', source.zoneCall),
    ('restoredZone', source.restoredZone),
  ]) {
    test('$name retains computation without unobserved state', () async {
      final function = program.functions.singleWhere(
        (body) =>
            body.target.name == name &&
            body.target.library.toString().endsWith(
              '/optimizer/fixtures/zone_state.dart',
            ),
      );
      final facts =
          ProgramOptimizer([
            const ProgramSimplification(),
            const ProgramCallSpecialization(),
            const ProgramStoragePromotion(),
            const ProgramStorageElimination(),
            const ProgramBranchSpecialization(),
            const ProgramLoopSpecialization(),
            const DirectCallInlining(),
            StackTraceLowering(heapRuntime.captureStackTrace),
          ]).run(
            program,
            [
              (
                target: function.target,
                arguments: [FlowValue.unknown(.integer)],
              ),
            ],
            allocationFailure: heapRuntime.allocationFailure,
            memoryLayoutFor: (graph) => ProgramLayout(
              graph.classes,
              nativeLayout: NativeLayout(Target.host()),
              functions: graph.functions,
              typeRuntime: heapRuntime.types,
            ),
          );
      expect(facts.returnedBy(function.target).isBottom, isFalse);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final value in [
        FlowIntegerRange.minimum,
        -4,
        0,
        41,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [value]),
          evaluate(value),
        );
      }
      expect(facts.definitions, {function.target});
      expect([
        for (final block in rewritten.blocks)
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ])
            ...operation.effects,
      ], isEmpty);
    });
  }
}
