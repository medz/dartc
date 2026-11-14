import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';
import '../support/ir_interpreter.dart';
import 'fixtures/reference_payload.dart' as source;

void main() {
  late IrProgram program;
  late ProgramLayout layout;
  IrFunction body(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.library.toString().endsWith(
          '/optimizer/fixtures/reference_payload.dart',
        ),
  );
  ProgramLayout layouts(IrProgram graph) => ProgramLayout(
    graph.classes,
    nativeLayout: NativeLayout(Target.host()),
    functions: graph.functions,
    typeRuntime: heapRuntime.types,
  );
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/reference_payload.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
    layout = layouts(program);
  });

  test('ordinary SDK lists carry overwritten function values through their reference payload', () {
    final function = body('replacedFunction');
    final facts = ProgramFlow(program, [
      (
        target: function.target,
        arguments: [FlowValue.constant(const Constant.integer(41))],
      ),
    ], memoryLayout: layout).facts;
    expect(
      facts.returnedBy(function.target).constant?.structuralKey,
      Constant.integer(source.replacedFunction(41)).structuralKey,
    );
    expect(facts.definitions, isNot(contains(body('unused').target)));
  });

  for (final name in ['replacedFunction', 'carriedInteger', 'carriedObject']) {
    test('source $name removes intermediate containers for runtime inputs', () {
      final function = body(name);
      final optimized =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ]).run(program, [
            (
              target: function.target,
              arguments: function.target.parameterTypes
                  .map(FlowValue.unknown)
                  .toList(),
            ),
          ], memoryLayoutFor: layouts);
      expect(optimized.returnedBy(function.target).isBottom, isFalse);
      final remaining = optimized.program.functions
          .where((body) => optimized.definitions.contains(body.target))
          .expand((body) => body.blocks)
          .expand(
            (block) => [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ],
          );
      expect(
        remaining.where(
          (operation) =>
              operation is NewPayload ||
              operation is Construct ||
              operation is LoadObjectReference ||
              operation is StoreObjectReference ||
              operation is LoadField ||
              operation is StoreField,
        ),
        isEmpty,
      );
      final rewritten =
          optimized.program.implementationOf(function.target) as IrFunction;
      final samples = name == 'carriedObject'
          ? <Object?>[null, 'kept', 37]
          : <Object?>[-4, 0, 41];
      for (final value in samples) {
        final expected = name == 'replacedFunction'
            ? source.replacedFunction(value as int)
            : value;
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [value]),
          expected,
        );
      }
    });
  }

  for (final (name, value) in [
    ('carriedInteger', const Constant.integer(37)),
    ('carriedObject', const Constant.string('kept')),
  ]) {
    test('generic SDK list payload retains $name', () {
      final function = body(name);
      final facts = ProgramFlow(program, [
        (target: function.target, arguments: [FlowValue.constant(value)]),
      ], memoryLayout: layout).facts;
      expect(
        facts.returnedBy(function.target).constant?.structuralKey,
        value.structuralKey,
      );
    });
  }
}
