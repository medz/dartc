import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/frame_lookup.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/storage_access.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:representation');
  final layouts = ProgramLayout([]);
  final members = MemberCalls(IrProgram([], []), {});

  test('function null comparisons do not inspect method identities', () {
    final method = FunctionTarget(
      uri,
      'method',
      .integer,
      [],
      owner: ClassType(uri, 'Receiver'),
      kind: .method,
    );
    final closures = ClosureStorage(
      [
        IrFunction(method, [
          Block(method.parameterTypes)
            ..finish(const Return(Constant.integer(0))),
        ]),
      ],
      boundMethods: [method],
    );
    final function = FunctionTarget(uri, 'isNull', .boolean, [
      method.signature.nullable,
    ]);
    for (final negated in [false, true]) {
      final entry = Block(function.parameterTypes);
      entry.finish(
        Return(
          entry.emit(
            Equals(
              entry.parameters.single,
              const Constant.nullValue(),
              negated: negated,
            ),
          ),
        ),
      );
      final body = FunctionRepresentation(
        IrFunction(function, [entry]),
        ProgramLayout(closures.classes, closureStorage: closures),
        CheckedCasts(),
        members,
        HeapPlan(FrameLookup()),
      );
      expect(
        body.instructions.values.expand((v) => v).whereType<TypeCast>(),
        isEmpty,
      );
      expect(
        body.instructions.values
            .expand((v) => v)
            .whereType<ObjectRuntimeType>(),
        isEmpty,
      );
    }
  });

  test(
    'storage operands retain live references and require real definitions',
    () {
      final field = InstanceField(ClassType(uri, 'Carrier'), 'value', .object);
      final target = FunctionTarget(uri, 'storage', .object, [.object]);
      final entry = Block(target.parameterTypes);
      final receiver = entry.parameters.single;
      final call = entry.emit(
        DirectCall(FunctionTarget(uri, 'collect', .voidType, []), []),
      );
      entry.finish(Return(receiver));
      final body = FunctionRepresentation(
        IrFunction(target, [entry]),
        layouts,
        CheckedCasts(),
        members,
        HeapPlan(FrameLookup()),
      );
      final read = StorageRead(field, receiver);
      final write = StorageWrite(field, receiver, read);
      body.instructions[entry] = [read, call, write];
      final flow = FunctionLiveness(body, body.inputsOf, {call});
      expect(body.inputsOf(read), [receiver]);
      expect(body.inputsOf(write), [receiver, read]);
      expect(flow.acrossCalls[call], {receiver, read});
      expect(entry.instructions, [call]);

      body.instructions[entry] = [write, call, read];
      expect(
        () => FunctionLiveness(body, body.inputsOf, {call}),
        throwsStateError,
      );
      body.instructions[entry] = [
        StorageRead(field, Block([.object]).parameters.single),
      ];
      expect(() => FunctionLiveness(body, body.inputsOf, {}), throwsStateError);

      final left = Block(), right = Block(), join = Block();
      body.blocks.addAll([left, right, join]);
      body.instructions[entry] = [];
      body.instructions[left] = [read];
      body.instructions[right] = [];
      body.instructions[join] = [write];
      body.ends[entry] = Branch(
        const Constant.boolean(true),
        Jump(left),
        Jump(right),
      );
      body.ends[left] = Jump(join);
      body.ends[right] = Jump(join);
      body.ends[join] = Return(receiver);
      expect(() => FunctionLiveness(body, body.inputsOf, {}), throwsStateError);
    },
  );

  test(
    'selected scalar returns are boxed before joining the semantic result',
    () {
      final face = ClassType(uri, 'Face');
      final type = ClassType(uri, 'Concrete', interfaces: [face]);
      final declaration = FunctionTarget(
        uri,
        'read',
        .number,
        [],
        owner: face,
        kind: .method,
        isAbstract: true,
      );
      final implementation = FunctionTarget(
        uri,
        'read',
        .floating,
        [],
        owner: type,
        kind: .method,
      );
      final entry = Block(), done = Block([.number]), failed = Block();
      final original = InstanceCall(declaration, ObjectConstant(type, {}), []);
      entry.finish(
        Invoke(
          original,
          onReturn: Jump(done, [original]),
          onThrow: Jump(failed),
        ),
      );
      done.finish(Return(done.parameters.single));
      failed.finish(const Return(Constant.floating(0)));
      final function = IrFunction(FunctionTarget(uri, 'caller', .number, []), [
        entry,
        done,
        failed,
      ]);
      final program = IrProgram(
        [
          IrClass(face, [], members: [declaration]),
          IrClass(type, [], members: [implementation]),
        ],
        [
          function,
          IrFunction(implementation, [
            Block(implementation.parameterTypes)
              ..finish(const Return(Constant.floating(1))),
          ]),
        ],
      );
      final body = FunctionRepresentation(
        function,
        ProgramLayout(program.classes),
        CheckedCasts(),
        MemberCalls(program, program.reachableFrom([function.target])),
        HeapPlan(FrameLookup()),
      );
      final selected = body.invocations.keys.single;
      expect(body.invocations[selected], same(implementation));
      expect(selected.type, ValueType.number);
      expect(body.typeOf(selected), ValueType.floating);
      expect(body.boxes.values.single, same(selected));
      expect(body.boxes.keys.single.type, ValueType.number);
      expect(body.aliases, {original});
      expect((entry.end as Invoke).operation, same(original));
      expect(
        body.ends.values
            .whereType<Invoke>()
            .where((end) => end.operation == selected)
            .single
            .onThrow
            .target,
        same(failed),
      );
    },
  );

  test(
    'checked field stores keep the receiver live and write only on success',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(uri, 'Cell', typeParameters: [t]);
      final field = InstanceField(owner, 'value', t);
      final target = FunctionTarget(
        uri,
        'write',
        .typeType,
        [owner, t],
        owner: owner,
        kind: .method,
      );
      final entry = Block(target.parameterTypes),
          done = Block(),
          failed = Block();
      final type = entry.emit(ReifyType(t));
      final store = StoreField(field, entry.parameters[1], entry.parameters[2]);
      entry.finish(Invoke(store, onReturn: Jump(done), onThrow: Jump(failed)));
      done.finish(Return(type));
      failed.finish(Return(type));
      final body = FunctionRepresentation(
        IrFunction(target, [entry, done, failed]),
        ProgramLayout([
          IrClass(owner, [field], members: [target]),
        ]),
        CheckedCasts(),
        members,
        HeapPlan(FrameLookup()),
      );
      final invoke = body.ends[entry] as Invoke;
      expect(invoke.operation, isA<TypeCast>());
      expect(invoke.onThrow.target, same(failed));
      expect(body.instructions[entry], isNot(contains(store)));
      expect(body.instructions[invoke.onReturn!.target], [store]);
      expect((body.ends[invoke.onReturn!.target] as Jump).target, same(done));
      expect(
        body.instructions[entry]!.whereType<ObjectRuntimeType>().map(
          (read) => read.operand,
        ),
        [entry.parameters[0], entry.parameters[1]],
      );
      final calls = body.instructions.values
          .expand((body) => body)
          .where(
            (instruction) =>
                instruction is DirectCall ||
                instruction is TypeCast ||
                instruction is NullCheck,
          )
          .toSet();
      final flow = FunctionLiveness(body, body.inputsOf, calls);
      expect(flow.acrossCalls[invoke.operation], contains(entry.parameters[1]));
      expect(body.inputsOf(store).last, same(invoke.operation));
      expect(
        entry.end,
        isA<Invoke>().having(
          (end) => end.operation,
          'original operation',
          same(store),
        ),
      );
    },
  );

  test('reifying a tested type keeps actual metadata and the promoted operand live', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final p = TypeParameterType('P')
      ..initializeBound(ValueType.object.nullable);
    final box = ClassType(uri, 'Box', typeParameters: [p]);
    final target = FunctionTarget(
      uri,
      'test',
      .object.nullable,
      [.object.nullable],
      typeParameters: [t],
    );
    final entry = Block(target.parameterTypes),
        yes = Block([
          box.instantiate([t]),
        ]),
        no = Block();
    final operand = entry.parameters.single;
    final test = entry.emit(TypeTest(operand, box.instantiate([t])));
    entry.finish(Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)));
    yes.finish(Return(yes.parameters.single));
    no.finish(Return(const Constant.nullValue()));
    final body = FunctionRepresentation(
      IrFunction(target, [entry, yes, no]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final actual = body.instructions[entry]!
        .whereType<ObjectRuntimeType>()
        .single;
    final reify = body.instructions[entry]!.whereType<DirectCall>().single;
    final flow = FunctionLiveness(body, body.inputsOf, {reify, test});
    expect(body.inputsOf(test), [actual, reify]);
    expect(flow.acrossCalls[reify], containsAll([actual, operand]));
    expect(flow.acrossCalls[test], contains(operand));
  });

  test('equivalent type templates share one ordered argument environment', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final u = TypeParameterType('U')
      ..initializeBound(ValueType.object.nullable);
    final a = FunctionType(
      .voidType,
      [t, u, t],
      namedParameters: {'a': false, 'b': false, 'c': false},
    );
    final b = FunctionType(
      .voidType,
      [u, t, t],
      namedParameters: {'b': false, 'a': false, 'c': false},
    );
    expect(a, b);
    final target = FunctionTarget(
      uri,
      'reify',
      .voidType,
      [],
      typeParameters: [t, u],
    );
    final entry = Block();
    entry.emit(ReifyType(a));
    entry.emit(ReifyType(b));
    entry.finish(const Return());
    final body = FunctionRepresentation(
      IrFunction(target, [entry]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final calls = body.instructions[entry]!.whereType<DirectCall>().toList();
    expect(calls, hasLength(2));
    expect(calls[0].target, same(calls[1].target));
    for (final call in calls) {
      expect(call.inputs, body.entryParameters);
      expect(call.target.parameterTypes, hasLength(2));
    }

    FunctionType withDefault(TypeParameterType value) {
      final binder = TypeParameterType('X')
        ..initializeBound(ValueType.object.nullable)
        ..initializeDefaultType(value);
      return FunctionType(.integer, [], typeParameters: [binder]);
    }

    final first = layouts.types.instantiate(withDefault(t));
    final second = layouts.types.instantiate(withDefault(u));
    expect(first.parameters, isEmpty);
    expect(second.target, same(first.target));
  });

  test('an earlier boxed argument is live while the next one allocates', () {
    final accept = FunctionTarget(uri, 'accept', .voidType, [.object, .object]);
    final caller = FunctionTarget(uri, 'caller', .voidType, [
      .integer,
      .floating,
    ]);
    final entry = Block(caller.parameterTypes);
    final call = entry.emit(DirectCall(accept, entry.parameters));
    entry.finish(const Return());
    final body = FunctionRepresentation(
      IrFunction(caller, [entry]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final boxes = body.boxes.keys.toList();
    final flow = FunctionLiveness(body, body.inputsOf, {...boxes, call});
    expect(boxes, hasLength(2));
    expect(flow.acrossCalls[boxes.last], {boxes.first});
    expect(flow.acrossCalls[call], isEmpty);
    expect(body.inputsOf(call), boxes);
    expect(entry.instructions, [call]);
  });

  test('edge conversions are conditional and unused conversions stay dead', () {
    final target = FunctionTarget(uri, 'branch', .integer, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        taken = Block([.object]),
        other = Block();
    entry.finish(
      Branch(
        entry.parameters[0],
        Jump(taken, [entry.parameters[1]]),
        Jump(other),
      ),
    );
    taken.finish(Return(const Constant.integer(1)));
    other.finish(Return(const Constant.integer(0)));
    final body = FunctionRepresentation(
      IrFunction(target, [entry, taken, other]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final flow = FunctionLiveness(body, body.inputsOf, body.boxes.keys.toSet());
    final branch = body.ends[entry] as Branch;
    expect(branch.ifFalse.target, same(other));
    expect(branch.ifTrue.target, isNot(same(taken)));
    expect(body.boxes.keys, hasLength(1));
    expect(flow.omitted, body.introduced);
    expect(flow.acrossCalls, isEmpty);
    expect(flow.liveIn[entry], {entry.parameters.first});
  });

  test('shared edges keep separate physical conversion operands', () {
    final target = FunctionTarget(uri, 'sharedEdge', .object, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes), done = Block([.object]);
    final edge = Jump(done, [entry.parameters.last]);
    entry.finish(Branch(entry.parameters.first, edge, edge));
    done.finish(Return(done.parameters.single));
    final body = FunctionRepresentation(
      IrFunction(target, [entry, done]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final branch = body.ends[entry] as Branch;
    expect(branch.ifTrue.target, isNot(same(branch.ifFalse.target)));
    for (final edge in [branch.ifTrue, branch.ifFalse]) {
      final transfer = body.ends[edge.target] as Jump;
      expect(body.argumentsOf(transfer), [
        body.instructions[edge.target]!.single,
      ]);
    }
  });

  test(
    'invoke arguments and outcomes convert at their own execution points',
    () {
      final target = FunctionTarget(uri, 'invoke', .object, [.integer]);
      final callee = FunctionTarget(uri, 'callee', .integer, [.object]);
      final handle = FunctionTarget(uri, 'handle', .object, [
        .object,
        .stackTrace,
        .object,
      ]);
      final entry = Block(target.parameterTypes), success = Block([.object]);
      final failure = Block([.object, .stackTrace, .object]);
      final argument = entry.parameters.single;
      final call = DirectCall(callee, [argument]);
      final invoke = Invoke(
        call,
        onReturn: Jump(success, [call]),
        onThrow: Jump(failure, [
          UnwindValue.exception,
          UnwindValue.stackTrace,
          argument,
        ]),
      );
      entry.finish(invoke);
      success.finish(Return(success.parameters.single));
      failure.finish(
        Return(failure.emit(DirectCall(handle, failure.parameters))),
      );
      final body = FunctionRepresentation(
        IrFunction(target, [entry, success, failure]),
        layouts,
        CheckedCasts(),
        members,
        HeapPlan(FrameLookup()),
      );
      final selected = body.ends[entry] as Invoke;
      final normalEdge = selected.onReturn!.target,
          failedEdge = selected.onThrow.target;
      final inputBox = body.instructions[entry]!.first;
      final normalBox = body.instructions[normalEdge]!.single;
      final failedBox = body.instructions[failedEdge]!.single;
      final flow = FunctionLiveness(body, body.inputsOf, {
        ...body.boxes.keys,
        call,
      });

      expect(body.instructions[entry], [inputBox, call]);
      expect(body.inputsOf(call), [inputBox]);
      expect(body.successors(entry), [selected.onReturn, selected.onThrow]);
      expect(selected.onReturn!.arguments, [call]);
      expect(selected.onThrow.arguments, invoke.onThrow.arguments);
      expect(flow.acrossCalls[call], {argument});
      expect(flow.acrossCalls[normalBox], isEmpty);
      expect(
        flow.acrossCalls[failedBox],
        failedEdge.parameters.take(2).toSet(),
      );
      expect(flow.liveIn[entry], {argument});
      expect(entry.instructions, isEmpty);
      expect(entry.end, same(invoke));
      expect(call.inputs, [argument]);
    },
  );

  test('boxing a thrown scalar keeps an existing trace alive', () {
    final target = FunctionTarget(uri, 'rethrow', .voidType, [
      .integer,
      .stackTrace,
    ]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Throw(entry.parameters.first, stackTrace: entry.parameters.last),
    );
    final body = FunctionRepresentation(
      IrFunction(target, [entry]),
      layouts,
      CheckedCasts(),
      members,
      HeapPlan(FrameLookup()),
    );
    final box = body.boxes.keys.single;
    final flow = FunctionLiveness(body, body.inputsOf, {box});
    final end = body.ends[entry] as Throw;
    expect(end.exception, same(box));
    expect(end.stackTrace, same(entry.parameters.last));
    expect(flow.acrossCalls[box], {entry.parameters.last});
    expect(flow.liveIn[entry], entry.parameters.toSet());
    expect(entry.instructions, isEmpty);
  });
}
