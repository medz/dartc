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
  ProgramFlowFacts optimize(
    IrFunction function, {
    List<FlowValue>? arguments,
  }) =>
      ProgramOptimizer(const [
        ProgramSimplification(),
        ProgramCallSpecialization(),
        ProgramStoragePromotion(),
        ProgramStorageElimination(),
        DirectCallInlining(),
      ]).run(program, [
        (
          target: function.target,
          arguments:
              arguments ??
              function.target.parameterTypes.map(FlowValue.unknown).toList(),
        ),
      ], memoryLayoutFor: layouts);
  Iterable<Instruction> operations(ProgramFlowFacts facts) => facts
      .program
      .functions
      .where((body) => facts.definitions.contains(body.target))
      .expand((body) => body.blocks)
      .expand(
        (block) => [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
      );
  void expectNoStorage(ProgramFlowFacts facts) => expect(
    operations(facts).where(
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

  for (final name in [
    'replacedFunction',
    'carriedInteger',
    'carriedObject',
    'aliasedInteger',
  ]) {
    test('source $name removes intermediate containers for runtime inputs', () {
      final function = body(name);
      final optimized = optimize(function);
      expect(optimized.returnedBy(function.target).isBottom, isFalse);
      expectNoStorage(optimized);
      final rewritten =
          optimized.program.implementationOf(function.target) as IrFunction;
      final samples = name == 'carriedObject'
          ? <Object?>[null, 'kept', 37]
          : <Object?>[-4, 0, 41];
      for (final value in samples) {
        final expected = switch (name) {
          'replacedFunction' => source.replacedFunction(value as int),
          'aliasedInteger' => source.aliasedInteger(value as int),
          _ => value,
        };
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [value]),
          expected,
        );
      }
    });
  }

  test('a runtime loop keeps its updates without retaining a private list', () {
    final function = body('loopInteger');
    final optimized = optimize(function);
    expectNoStorage(optimized);
    final rewritten =
        optimized.program.implementationOf(function.target) as IrFunction;
    for (final value in [-4, 0, 41]) {
      for (final count in [-2, 0, 1, 4, 11]) {
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [value, count]),
          source.loopInteger(value, count),
        );
      }
    }
  });

  test(
    'an external observer retains list storage and can change the read value',
    () {
      final function = body('observedInteger');
      final optimized = optimize(function);
      final retained = operations(optimized).toList();
      expect(retained.whereType<NewPayload>(), isNotEmpty);
      expect(retained.whereType<StoreObjectReference>(), isNotEmpty);
      expect(
        retained.whereType<FunctionCall>().any(optimized.hasUnknownCall),
        isTrue,
      );
      final rewritten =
          optimized.program.implementationOf(function.target) as IrFunction;
      for (final block in rewritten.blocks) {
        if (block.end case Return(:final value?)) {
          expect(
            optimized.equivalentsOf(value),
            isNot(contains(rewritten.entry.parameters.first)),
          );
        }
      }
    },
  );

  for (final index in [-1, 1]) {
    test('a proven invalid list index $index preserves its exception', () {
      final function = body('checkedInteger');
      final arguments = [
        FlowValue.unknown(.integer),
        FlowValue.constant(Constant.integer(index)),
      ];
      expect(() => source.checkedInteger(37, index), throwsRangeError);
      for (final facts in [
        ProgramFlow(program, [
          (target: function.target, arguments: arguments),
        ], memoryLayout: layout).facts,
        optimize(function, arguments: arguments),
      ]) {
        expect(facts.returnedBy(function.target).isBottom, isTrue);
        expect(facts.thrownBy(function.target).exception.isBottom, isFalse);
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
