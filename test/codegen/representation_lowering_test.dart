import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

Iterable<Instruction> operations(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

IrProgram lower(IrProgram program) => RepresentationLowering().lower(
  program,
  program.functions.map((function) => function.target),
);

void main() {
  test('partial demand postpones dormant operation and phi conversions', () {
    final slot = GlobalVariable(
      Uri.parse('memory:partial-shape'),
      'value',
      .integer.nullable,
    );
    final target = FunctionTarget(null, 'conditionalStore', .object, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block([ValueType.object]);
    entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    yes.finish(const Return(Constant.string('observed')));
    no.emit(StoreGlobal(slot, entry.parameters.last));
    no.finish(Jump(join, [entry.parameters.last]));
    join.finish(Return(join.parameters.single));
    final source = IrProgram(
      [],
      [
        IrFunction(target, [entry, yes, no, join]),
      ],
      globals: [slot],
    );
    ProgramFlowFacts solve(IrProgram program, FlowValue condition) =>
        ProgramFlow(program, [
          (
            target: target,
            arguments: [condition, FlowValue.unknown(ValueType.integer)],
          ),
        ]).facts;
    final partial = RepresentationLowering().run(
      solve(source, FlowValue.constant(const Constant.boolean(true))),
    );
    final dormant = partial.implementationOf(target) as IrFunction;
    expect(operations(dormant).whereType<StoreGlobal>(), hasLength(1));
    expect(operations(dormant).whereType<MaterializeValue>(), isEmpty);
    expect(() => partial.executionShapes!.verify(dormant), throwsStateError);
    final broader = RepresentationLowering().run(
      solve(partial, FlowValue.unknown(ValueType.boolean)),
    );
    final actual = broader.implementationOf(target) as IrFunction;
    expect(operations(actual).whereType<MaterializeValue>(), hasLength(2));
    broader.executionShapes!.verify(actual);
    expect(IrInterpreter(broader, {}).run(actual, [false, 42]), 42);
  });

  test('a reached nonreturning operation does not demand its dormant tail', () {
    final fail = FunctionTarget(null, 'failBeforeTail', .integer, []);
    final failBlock = Block()..finish(Throw(const Constant.string('failure')));
    final target = FunctionTarget(null, 'unreachableReturn', .object, [
      .integer,
    ]);
    final entry = Block(target.parameterTypes);
    entry.emit(DirectCall(fail, []));
    entry.finish(Return(entry.parameters.single));
    final source = IrProgram([], [
      IrFunction(fail, [failBlock]),
      IrFunction(target, [entry]),
    ]);
    final facts = ProgramFlow(source, const [], openEntries: [target]).facts;
    final partial = RepresentationLowering().run(facts);
    final body = partial.implementationOf(target) as IrFunction;
    expect(body.entry.end, isA<Return>());
    expect(operations(body).whereType<DirectCall>(), hasLength(1));
    expect(operations(body).whereType<MaterializeValue>(), isEmpty);
    expect(() => partial.executionShapes!.verify(body), throwsStateError);
  });

  test('partial demand retains dormant transfers for a broader next solve', () {
    final target = FunctionTarget(null, 'conditionalCarrier', .object, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    yes.finish(const Return(Constant.string('observed')));
    no.finish(Return(entry.parameters.last));
    final source = IrProgram([], [
      IrFunction(target, [entry, yes, no]),
    ]);
    ProgramFlowFacts solve(IrProgram program, FlowValue condition) =>
        ProgramFlow(program, [
          (
            target: target,
            arguments: [condition, FlowValue.unknown(ValueType.integer)],
          ),
        ]).facts;
    final partial = RepresentationLowering().run(
      solve(source, FlowValue.constant(const Constant.boolean(true))),
    );
    final body = partial.implementationOf(target) as IrFunction;
    expect(body.blocks, hasLength(3));
    expect(operations(body).whereType<MaterializeValue>(), isEmpty);
    expect(() => partial.executionShapes!.verify(body), throwsStateError);

    final pruned = const ProgramSimplification().run(
      solve(partial, FlowValue.constant(const Constant.boolean(true))),
    );
    pruned.executionShapes!.verify(
      pruned.implementationOf(target) as IrFunction,
    );
    final broader = RepresentationLowering().run(
      solve(partial, FlowValue.unknown(ValueType.boolean)),
    );
    final complete = broader.implementationOf(target) as IrFunction;
    expect(operations(complete).whereType<MaterializeValue>(), hasLength(1));
    broader.executionShapes!.verify(complete);
    for (final choice in [false, true]) {
      expect(
        IrInterpreter(broader, {}).run(complete, [choice, 42]),
        choice ? 'observed' : 42,
      );
    }
    final strict = lower(source);
    expect(
      operations(strict.implementationOf(target) as IrFunction)
          .whereType<MaterializeValue>(),
      hasLength(1),
    );
  });
  test('branch conditions project a reference-carried boolean', () {
    final target = FunctionTarget(null, 'predicate', .integer, [.boolean]);
    final entry = Block(target.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    yes.finish(const Return(Constant.integer(1)));
    no.finish(const Return(Constant.integer(0)));
    final source = IrFunction(target, [entry, yes, no]);
    final shapes = ExecutionShapes(
      entries: {
        target: ExecutionSignature([
          ExecutionShape.reference,
        ], ExecutionShape.word),
      },
    );
    expect(() => shapes.verify(source), throwsStateError);
    final program = lower(IrProgram([], [source], executionShapes: shapes));
    final body = program.implementationOf(target) as IrFunction;
    expect((body.entry.end as Branch).condition, isA<ProjectValue>());
    expect(operations(body).whereType<MaterializeValue>(), isEmpty);
    shapes.verify(body);
  });
  for (final runtimeType in [false, true]) {
    test(
      'semantic ${runtimeType ? 'runtimeType' : 'type test'} preserves a scalar operand',
      () {
        final target = FunctionTarget(
          null,
          'query',
          runtimeType ? .typeType : .boolean,
          [.integer],
        );
        final entry = Block(target.parameterTypes);
        final view = entry.emit(
          TypeView(entry.parameters.single, ValueType.object),
        );
        final query = entry.emit(
          runtimeType
              ? ObjectRuntimeType(view)
              : TypeTest(view, ValueType.integer),
        );
        entry.finish(Return(query));
        final program = lower(
          IrProgram([], [
            IrFunction(target, [entry]),
          ]),
        );
        final body = program.implementationOf(target) as IrFunction;
        expect(operations(body).whereType<MaterializeValue>(), isEmpty);
        expect(operations(body).whereType<ConstantCarrier>(), isEmpty);
        final actualQuery = operations(body)
            .singleWhere((v) => v is TypeTest || v is ObjectRuntimeType);
        expect(program.executionShapes!.inputShapesOf(body, actualQuery), [
          ExecutionShape.word,
        ]);
        final runner = IrInterpreter(program, {});
        final oracle = IrFunction(
          FunctionTarget(null, 'answer', .typeType, []),
          [Block()..finish(Return(TypeConstant(.integer)))],
        );
        for (final input in [-7, 0, 42]) {
          expect(
            runner.run(body, [input]),
            runtimeType ? runner.run(oracle, []) : true,
          );
        }
      },
    );
  }
  test(
    'nullable shared slot adapts its actual write and preserves int semantics',
    () {
      final slot = GlobalVariable(
        Uri.parse('memory:shape'),
        'shared',
        .integer.nullable,
      );
      final write = FunctionTarget(null, 'write', .voidType, [.integer]);
      final block = Block(write.parameterTypes);
      block.emit(StoreGlobal(slot, block.parameters.single));
      block.finish(const Return());
      final program = lower(
        IrProgram(
          [],
          [
            IrFunction(write, [block]),
          ],
          globals: [slot],
        ),
      );
      final body = program.implementationOf(write) as IrFunction;
      final materialized = operations(body)
          .whereType<MaterializeValue>()
          .single;
      expect(materialized.type, ValueType.integer);
      expect(
        operations(body).whereType<StoreGlobal>().single.value,
        same(materialized),
      );
      expect(
        program.executionShapes!.shapeOf(body, materialized),
        ExecutionShape.reference,
      );
      expect(lower(program), same(program));
    },
  );

  test(
    'one semantic int has a reference result and explicit call adaptation',
    () {
      final callee = FunctionTarget(null, 'callee', .integer, [.integer]);
      final body = Block(callee.parameterTypes)
        ..finish(Return(const Constant.integer(9)));
      final caller = FunctionTarget(null, 'caller', .integer, [.integer]);
      final call = Block(caller.parameterTypes);
      final invoked = call.emit(DirectCall(callee, call.parameters));
      call.finish(
        Return(call.emit(IntBinary(.add, invoked, const Constant.integer(1)))),
      );
      final shapes = ExecutionShapes(
        entries: {
          callee: ExecutionSignature([
            ExecutionShape.reference,
          ], ExecutionShape.reference),
        },
      );
      final program = lower(
        IrProgram([], [
          IrFunction(caller, [call]),
          IrFunction(callee, [body]),
        ], executionShapes: shapes),
      );
      final result = program.implementationOf(caller) as IrFunction;
      expect(operations(result).whereType<MaterializeValue>(), hasLength(1));
      expect(operations(result).whereType<ProjectValue>(), hasLength(1));
      final actual = operations(result).whereType<DirectCall>().single;
      expect(actual.type, ValueType.integer);
      expect(shapes.shapeOf(result, actual), ExecutionShape.reference);
      expect(
        operations(program.implementationOf(callee) as IrFunction)
            .whereType<ConstantCarrier>(),
        hasLength(1),
      );
    },
  );

  test('phi adaptation lives on its actual branch edge', () {
    final root = FunctionTarget(null, 'phi', .integer.nullable, [
      .boolean,
      .integer,
    ]);
    final start = Block(root.parameterTypes),
        join = Block([ValueType.integer.nullable]);
    start.finish(
      Branch(
        start.parameters.first,
        Jump(join, [start.parameters.last]),
        Jump(join, [const Constant.nullValue()]),
      ),
    );
    join.finish(Return(join.parameters.single));
    final program = lower(
      IrProgram([], [
        IrFunction(root, [start, join]),
      ]),
    );
    final body = program.implementationOf(root) as IrFunction;
    expect(body.entry.instructions.whereType<MaterializeValue>(), isEmpty);
    final branch = body.entry.end as Branch;
    expect(
      branch.ifTrue.target.instructions.whereType<MaterializeValue>(),
      hasLength(1),
    );
    expect(branch.ifFalse.target, isNot(same(branch.ifTrue.target)));
    program.executionShapes!.verify(body);
  });

  test('an adapting edge retains the scalar proof behind a broad view', () {
    final root = FunctionTarget(null, 'viewPhi', .object, [.boolean, .integer]);
    final start = Block(root.parameterTypes), join = Block([ValueType.object]);
    final view = start.emit(TypeView(start.parameters.last, ValueType.object));
    start.finish(
      Branch(
        start.parameters.first,
        Jump(join, [view]),
        Jump(join, [const Constant.string('other')]),
      ),
    );
    join.finish(Return(join.parameters.single));
    final program = lower(
      IrProgram([], [
        IrFunction(root, [start, join]),
      ]),
    );
    final body = program.implementationOf(root) as IrFunction;
    final branch = body.entry.end as Branch;
    final allocation = branch.ifTrue.target.instructions
        .whereType<MaterializeValue>()
        .single;
    expect(allocation.value.type, ValueType.integer);
    expect(branch.ifTrue.arguments.single.type, ValueType.integer);
    expect(operations(body).whereType<UncheckedCast>(), isEmpty);
    program.executionShapes!.verify(body);
  });

  test('call adaptation retains the original allocation failure handler', () {
    final callee = FunctionTarget(null, 'target', .integer, [.object]);
    final root = FunctionTarget(null, 'caught', .integer, [.integer]);
    final start = Block(root.parameterTypes),
        returned = Block([ValueType.integer]),
        failed = Block();
    final call = DirectCall(callee, start.parameters);
    start.finish(
      Invoke(call, onReturn: Jump(returned, [call]), onThrow: Jump(failed)),
    );
    returned.finish(Return(returned.parameters.single));
    failed.finish(const Return(Constant.integer(73)));
    final program = lower(
      IrProgram(
        [],
        [
          IrFunction(root, [start, returned, failed]),
        ],
        externals: [IrExternal(callee)],
      ),
    );
    final body = program.implementationOf(root) as IrFunction;
    final allocation = body.entry.end as Invoke;
    expect(allocation.operation, isA<MaterializeValue>());
    expect(
      (allocation.onThrow.target.end as Return).value,
      const Constant.integer(73),
    );
    final native = body.blocks
        .map((b) => b.end)
        .whereType<Invoke>()
        .singleWhere((end) => end.operation is DirectCall);
    expect(native.onThrow.target, same(allocation.onThrow.target));
  });

  test('discarded language upcast does not request a carrier conversion', () {
    final root = FunctionTarget(null, 'view', .integer, [.integer]);
    final block = Block(root.parameterTypes);
    block.emit(TypeView(block.parameters.single, ValueType.object));
    block.finish(Return(block.parameters.single));
    final program = lower(
      IrProgram([], [
        IrFunction(root, [block]),
      ]),
    );
    final body = program.implementationOf(root) as IrFunction;
    expect(operations(body).whereType<MaterializeValue>(), isEmpty);
  });

  test(
    'physical memory rejects an unconverted scalar carrier at verification',
    () {
      final root = FunctionTarget(null, 'raw', .integer, [.integer]);
      final block = Block(root.parameterTypes);
      block.finish(
        Return(
          block.emit(
            LoadObjectData(
              block.parameters.single,
              const Constant.integer(0),
              NativeScalarType(Int64),
            ),
          ),
        ),
      );
      final body = IrFunction(root, [block]);
      expect(() => ExecutionShapes.defaults.verify(body), throwsStateError);
    },
  );

  test('constant replacement preserves a reference carrier', () {
    final root = FunctionTarget(null, 'constant', .object, []);
    final block = Block();
    final value = block.emit(ConstantCarrier(const Constant.integer(42)));
    block.finish(Return(value));
    final body = IrFunction(root, [
      block,
    ], execution: FunctionExecution({value: ExecutionShape.reference}));
    final rewritten = FunctionRewrite(
      body,
      replacements: {value: const Constant.integer(42)},
    ).run();
    expect(operations(rewritten).whereType<ConstantCarrier>(), hasLength(1));
    ExecutionShapes.defaults.verify(rewritten);
    expect(rewritten, same(body));
  });
}
