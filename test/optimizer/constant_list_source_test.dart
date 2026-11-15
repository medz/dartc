import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/constant_list.dart' as source;

void main() {
  late IrProgram program;
  ProgramLayout layouts(IrProgram graph) => ProgramLayout(
    graph.classes,
    nativeLayout: NativeLayout(Target.host()),
    functions: graph.functions,
    typeRuntime: heapRuntime.types,
  );
  IrFunction body(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.library.toString().endsWith(
          '/optimizer/fixtures/constant_list.dart',
        ),
  );
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/constant_list.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });

  test(
    'source constant lists resolve known elements through ordinary methods',
    () {
      for (final (name, arguments, expected) in [
        (
          'read',
          [FlowValue.constant(const Constant.integer(1))],
          source.read(1),
        ),
        ('nested', <FlowValue>[], source.nested()),
      ]) {
        final function = body(name);
        final facts = ProgramFlow(program, [
          (target: function.target, arguments: arguments),
        ], memoryLayout: layouts(program)).facts;
        expect(
          facts.returnedBy(function.target).constant?.structuralKey,
          Constant.string(expected).structuralKey,
        );
      }
    },
  );

  test('source constant lists preserve selection and index errors for runtime input', () {
    final function = body('checkedRead');
    final optimized =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramCallSpecialization(),
          ProgramStoragePromotion(),
          ProgramStorageElimination(),
          DirectCallInlining(),
        ]).run(program, [
          (target: function.target, arguments: [FlowValue.unknown(.integer)]),
        ], memoryLayoutFor: layouts);
    final rewritten =
        optimized.program.implementationOf(function.target) as IrFunction;
    for (final index in [-1, 0, 1, 2]) {
      expect(
        IrInterpreter(optimized.program, {}).run(rewritten, [index]),
        source.checkedRead(index),
      );
    }
  });

  test(
    'uniform source list keeps its input guard and needs no list computation',
    () {
      final function = body('uniform');
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ]).run(program, [
            (target: function.target, arguments: [FlowValue.unknown(.integer)]),
          ], memoryLayoutFor: layouts);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final index in [
        FlowIntegerRange.minimum,
        -1,
        0,
        1,
        2,
        3,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [index]),
          source.uniform(index),
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

  test(
    'character decoding primitive reads the normalized storage contract',
    () {
      final call = body('fromCodes').entry.instructions
          .whereType<DirectCall>()
          .singleWhere((call) => call.target.name == 'fromCharCodes');
      final codes = switch (call.inputs.first) {
        TypeView(:final operand) => operand,
        final value => value,
      };
      expect(codes, isA<ObjectConstant>());
      final target = FunctionTarget(
        Uri.parse('memory:normalized-codes'),
        'decode',
        .string,
        [],
      );
      final block = Block();
      block.finish(
        Return(
          block.emit(StringFromCharCodes(codes, const Constant.integer(0))),
        ),
      );
      final graph = IrProgram(
        program.classes,
        [
          ...program.functions,
          IrFunction(target, [block]),
        ],
        globals: program.globals,
        externals: program.externals,
      );
      final facts = ProgramFlow(graph, [
        (target: target, arguments: []),
      ], memoryLayout: layouts(graph)).facts;
      expect(
        facts.returnedBy(target).constant?.structuralKey,
        Constant.string(source.fromCodes()).structuralKey,
      );
    },
  );

  test('source UTF-16 reads leave only their known computed result', () {
    final function = body('literalUnits');
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
          [(target: function.target, arguments: [])],
          allocationFailure: heapRuntime.allocationFailure,
          memoryLayoutFor: layouts,
        );
    final rewritten =
        facts.program.implementationOf(function.target) as IrFunction;
    expect(
      facts.returnedBy(function.target).constant?.structuralKey,
      Constant.integer(source.literalUnits()).structuralKey,
    );
    expect(
      IrInterpreter(facts.program, {}).run(rewritten, []),
      source.literalUnits(),
    );
    expect(facts.definitions, {function.target});
    expect(rewritten.entry.instructions, isEmpty);
  });
}
