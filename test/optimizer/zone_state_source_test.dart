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
  test(
    'zoneCall retains computation without unobserved zone storage',
    () async {
      await prepareRuntime('test/optimizer/fixtures/zone_state.dart');
      final program = ProgramNormalization(
        heapRuntime.program,
        runtime: heapRuntime,
      ).run();
      final function = program.functions.singleWhere(
        (body) =>
            body.target.name == 'zoneCall' &&
            body.target.library.toString().endsWith(
              '/optimizer/fixtures/zone_state.dart',
            ),
      );
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ]).run(
            program,
            [
              (
                target: function.target,
                arguments: [FlowValue.unknown(.integer)],
              ),
            ],
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
          source.zoneCall(value),
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
    },
  );
}
