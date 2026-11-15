import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/native_storage.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/native_storage.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  IrFunction entry(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.library.toString().endsWith(
          '/optimizer/fixtures/native_storage.dart',
        ),
  );
  ProgramFlowFacts optimize(IrFunction function) =>
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
            arguments: function.target.parameterTypes
                .map(FlowValue.unknown)
                .toList(),
          ),
        ],
        memoryLayoutFor: (graph) => ProgramLayout(
          graph.classes,
          nativeLayout: NativeLayout(Target.host()),
          functions: graph.functions,
          typeRuntime: heapRuntime.types,
        ),
      );

  test('a bounded runtime index needs no zeroed byte storage', () {
    final function = entry('zeroByte'), facts = optimize(function);
    final body = facts.program.implementationOf(function.target) as IrFunction;
    for (final index in [
      FlowIntegerRange.minimum,
      -1,
      0,
      7,
      15,
      16,
      FlowIntegerRange.maximum,
    ]) {
      expect(
        IrInterpreter(facts.program, {}).run(body, [index]),
        source.zeroByte(index),
      );
    }
    expect(facts.definitions, {function.target});
    expect([
      for (final block in body.blocks)
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ])
          ...operation.effects,
    ], isEmpty);
  });

  for (final name in ['dartAttached', 'nativeAttached']) {
    test('source $name retains attached storage and lifetime protection', () {
      final facts = optimize(entry(name));
      final operations = [
        for (final body in facts.program.functions)
          if (facts.definitions.contains(body.target))
            for (final block in body.blocks) ...block.instructions,
      ];
      expect(operations.whereType<NewPayload>(), isNotEmpty);
      expect(operations.whereType<KeepAlive>(), isNotEmpty);
    });
  }
}
