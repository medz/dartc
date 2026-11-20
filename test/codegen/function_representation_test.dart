import 'package:dartc/target.dart';
import 'package:dartc/codegen.dart'
    show RepresentationLowering, AllocationLowering, CallableImplementations, CallableLowering;
import 'package:dartc/abi.dart';

import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/native_call_lowering.dart';
import 'package:dartc/src/codegen/native_view_lowering.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/storage_access.dart';
import 'package:dartc/src/codegen/native_invocation.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  final uri = Uri.parse('memory:representation');
  setUpAll(prepareRuntime);
  late final layouts = ProgramLayout(
    [],
    typeRuntime: heapRuntime.types,
    nativeLayout: NativeLayout(const Target(.linux, .arm64)),
  );
  final members = MemberCalls(IrProgram([], []), {});

  test(
    'a proven closure calls its own entry without redispatching its carrier',
    () {
      final outer = FunctionTarget(uri, 'capture', .integer, [.integer]);
      final selected = FunctionTarget(
        uri,
        'selected',
        .integer,
        [.integer],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 1,
        captures: [.integer],
      );
      final other = FunctionTarget(
        uri,
        'other',
        .integer,
        [.integer],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 2,
        captures: [.integer],
      );
      final entry = Block(outer.parameterTypes);
      final closure = entry.emit(MakeClosure(selected, entry.parameters));
      entry.finish(
        Return(
          entry.emit(
            FunctionCall(
              closure,
              [const Constant.integer(7)],
              const {},
              const [],
              selected,
            ),
          ),
        ),
      );
      final source = IrFunction(outer, [entry]);
      final bodies = [
        source,
        for (final target in [selected, other])
          IrFunction(target, [
            Block(target.parameterTypes)
              ..finish(const Return(Constant.integer(0))),
          ]),
      ];
      final original = IrProgram([], bodies);
      final implementations = CallableImplementations();
      final lowered = CallableLowering(implementations).run(
        ProgramFlow(original, const [], openEntries: [outer]).facts,
      );
      final initialFacts = ProgramFlow(lowered, const [], openEntries: [outer]).facts;
      final program = const ProgramCallSpecialization().run(initialFacts);
      final facts = ProgramFlow(program, const [], openEntries: [outer]).facts;
      final adapter = implementations.functions.single;
      expect(
        (program.implementationOf(outer)! as IrFunction).blocks
            .expand((block) => block.instructions).whereType<DirectCall>()
            .map((call) => call.target),
        contains(adapter.target),
      );
      final storage = ClosureStorage(program.functions,
          storageDeclarations: program.classes,
          callableImplementations: implementations);
      final layout = ProgramLayout(
        storage.classes,
        closureStorage: storage,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        typeRuntime: heapRuntime.types,
      );
      final body = FunctionRepresentation(
        adapter,
        layout,
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        MemberCalls(program, facts.definitions, callTypes: facts),
        HeapPlan(),
      )..prune();
      final operations = body.instructions.values.expand((values) => values);
      final call = operations.whereType<DirectCall>()
          .singleWhere((call) => call.target == selected);
      expect(body.callees, isNot(contains(other)));
      expect(body.ends.values.whereType<Branch>(), isEmpty);
      final capture = operations.whereType<StorageRead>().singleWhere(
        (read) => read.field == storage.closures[selected]!.captures.single,
      );
      final input = body.inputsOf(call).toList();
      expect(body.aliases, contains(input[1]));
      expect(body.inputsOf(input[1]).single, same(capture));
      expect(input.last, same(adapter.entry.parameters[1]));
      expect(operations.whereType<StorageRead>().where(
          (read) => read.field == FunctionStorage.entries), isEmpty);

    },
  );

  test('non-generic member access does not prepare owner type arguments', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType(uri, 'Container', typeParameters: [t]);
    final getter = FunctionTarget(
      uri,
      'length',
      .integer,
      [],
      owner: owner,
      kind: .getter,
    );
    final target = FunctionTarget(uri, 'read', .integer, [
      owner.instantiate([.integer]),
    ]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          DirectCall(
            getter,
            entry.parameters,
            ownerType: owner.instantiate([.integer]),
          ),
        ),
      ),
    );
    final layout = ProgramLayout([
      IrClass(owner, [], members: [getter]),
    ], nativeLayout: NativeLayout(const Target(.linux, .arm64)));
    final representation = FunctionRepresentation(
      IrFunction(target, [entry]),
      layout,
      CheckedCasts(failure: heapRuntime.typeCheckFailure),
      members,
      HeapPlan(),
    );
    expect(representation.invocations.values, [getter]);
    expect(layout.relations.functions, isEmpty);
  });

  test(
    'borrowed owners remain live through the selected native invocation',
    () {
      final target = FunctionTarget(uri, 'borrow', .voidType, [.object]);
      final entry = Block(target.parameterTypes);
      final owner = entry.parameters.single;
      final before = entry.emit(
        DirectCall(FunctionTarget(uri, 'collect', .voidType, []), []),
      );
      final symbol = NativeSymbolAddress(
        NativeReference(
          'test',
          'borrow',
          NativeFunctionType(
            NativeSignature(ffi.Void, [ffi.Pointer<ffi.Void>]),
          ),
          isLeaf: true,
        ),
      );
      entry.emit(symbol);
      entry.emit(
        NativeCall.symbol(
          symbol,
          FunctionType(.voidType, [
            FfiTypes.pointerTypes[ffi.Pointer<ffi.Void>]!,
          ]),
          [const Constant.integer(0)],
          borrowedOwners: {0: owner},
        ),
      );
      entry.finish(Return());
      final lowered = NativeCallLowering()
          .lower(
            IrProgram([], [
              IrFunction(target, [entry]),
            ]),
          )
          .functions
          .single;
      final boundary = lowered.blocks
          .expand((block) => block.instructions)
          .whereType<RawNativeCall>()
          .single;
      expect(boundary.borrowedArguments, {0});
      expect(
        (boundary.mapInputs(
          (value) => value,
        ) as RawNativeCall).borrowedArguments,
        {0},
      );
      final body = FunctionRepresentation(
        lowered,
        layouts,
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
      );
      final operations = body.instructions.values.expand((values) => values);
      final call = operations.whereType<NativeInvocation>().single;
      final prior = operations.whereType<DirectCall>().singleWhere(
        (call) => call.target == before.target,
      );
      final actualOwner = lowered.entry.parameters.single;
      final flow = FunctionLiveness(body, body.inputsOf, {prior, call});
      expect(flow.acrossCalls[prior], contains(actualOwner));
      expect(flow.acrossCalls[call], contains(actualOwner));
    },
  );

  test('aggregate native calls retain distinct leaf and reentry contracts', () {
    final packet = NativeCompoundType('Packet', [
      NativeField('value', NativeScalarType(ffi.Int64)),
    ]);
    final packetType = ClassType(uri, 'Packet', nativeType: packet);
    final signature = NativeSignature.types(NativeScalarType(ffi.Int64), [
      packet,
    ]);
    final layout = ProgramLayout(
      [],
      typeRuntime: heapRuntime.types,
      nativeLayout: NativeLayout(const Target(.linux, .arm64)),
    );
    final targets = <bool, FunctionTarget>{};
    for (final isLeaf in [true, false, true]) {
      final target = FunctionTarget(uri, 'callPacket', .integer, [packetType]);
      final entry = Block(target.parameterTypes);
      final symbol = entry.emit(
        NativeSymbolAddress(
          NativeReference(
            'fixture',
            'callPacket',
            NativeFunctionType(signature),
            isLeaf: isLeaf,
          ),
        ),
      );
      entry.finish(
        Return(
          entry.emit(
            NativeCall.symbol(
              symbol,
              FunctionType(.integer, [packetType]),
              entry.parameters,
            ),
          ),
        ),
      );
      final nativeCalls = NativeCallLowering().lower(
        IrProgram([], [
          IrFunction(target, [entry]),
        ]),
      );
      final lowered = NativeViewLowering(
        layout.native,
      ).lower(nativeCalls, [target]).implementationOf(target) as IrFunction;
      final body = FunctionRepresentation(
        lowered,
        layout,
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
      );
      final adapter = body.invocations.values.singleWhere(
        layout.nativeCalls.entries.containsKey,
      );
      expect(layout.nativeCalls.entries[adapter], (
        signature: signature,
        isLeaf: isLeaf,
      ));
      if (targets[isLeaf] case final previous?) expect(adapter, same(previous));
      targets[isLeaf] = adapter;
    }
    expect(targets[true], isNot(same(targets[false])));
    expect(layout.nativeCalls.entries, hasLength(2));
  });

  test(
    'trusted casts stay pure and actual return boundaries adapt carriers',
    () {
      for (final (source, result) in <(ValueType, ValueType)>[
        (.object.nullable, FunctionType(.integer, [.integer])),
        (.object, .integer),
        (.object, .floating),
        (.integer, .object),
        (.floating, .object),
      ]) {
        final target = FunctionTarget(uri, 'view', result, [source]);
        final entry = Block(target.parameterTypes);
        final cast = entry.emit(UncheckedCast(entry.parameters.single, result));
        entry.finish(Return(cast));
        final normalized = _adapt(IrFunction(target, [entry]));
        expect(cast.effects, isEmpty);
        expect(_ops(normalized).whereType<TypeCast>(), isEmpty);
        final materializes = _ops(normalized).whereType<MaterializeValue>();
        expect(
          materializes.length,
          source == .integer || source == .floating ? 1 : 0,
        );
        final projects = _ops(normalized).whereType<ProjectValue>();
        expect(
          projects.length,
          result == .integer || result == .floating ? 1 : 0,
        );
        final selected = _selectAdapted(normalized);
        expect(
          selected.instructions.values
              .expand((ops) => ops)
              .whereType<MaterializeValue>(),
          isEmpty,
        );
        final text = StringBuffer();
        normalized.writeTo(text);
        expect(text.toString(), contains('unchecked'));
      }
      final cell = NewCell(CellType(.integer), const Constant.integer(1));
      expect(() => UncheckedCast(cell, .object), throwsArgumentError);
      expect(
        () => UncheckedCast(const Constant.integer(1), cell.type),
        throwsArgumentError,
      );
    },
  );

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
        ProgramLayout(
          closures.classes,
          closureStorage: closures,
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        ),
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
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
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
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
    'selected scalar return adaptation enters ordinary IR before selection',
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
      final entry = Block(), done = Block([ValueType.number]), failed = Block();
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
      final target = FunctionTarget(uri, 'caller', .number, []);
      var program = IrProgram(
        [
          IrClass(face, [], members: [declaration]),
          IrClass(type, [], members: [implementation]),
        ],
        [
          IrFunction(target, [entry, done, failed]),
          IrFunction(implementation, [
            Block(implementation.parameterTypes)
              ..finish(const Return(Constant.floating(1))),
          ]),
        ],
      );
      program = RepresentationLowering().lower(program, [
        target, implementation,
      ]);
      final facts = ProgramFlow(program, [
        (target: target, arguments: []),
      ]).facts;
      final resolved = const ProgramCallSpecialization().run(facts);
      final body = _adapt(
        resolved.implementationOf(target) as IrFunction,
        classes: resolved.classes,
        companions: resolved.functions.where((f) => f.target != target),
      );
      expect(
        _ops(body)
            .whereType<DirectCall>()
            .any((op) => op.target == implementation),
        isTrue,
      );
      expect(_ops(body).whereType<MaterializeValue>(), hasLength(1));
      expect(_ops(body).whereType<InstanceCall>(), isEmpty);
      expect((entry.end as Invoke).operation, same(original));
      _selectAdapted(
        body,
        classes: resolved.classes,
        companions: resolved.functions.where((f) => f.target != target),
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
        ], nativeLayout: NativeLayout(const Target(.linux, .arm64))),
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
      );
      final invoke = body.ends.values.whereType<Invoke>().singleWhere(
        (end) => end.operation is TypeCast,
      );
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
      CheckedCasts(failure: heapRuntime.typeCheckFailure),
      members,
      HeapPlan(),
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
      CheckedCasts(failure: heapRuntime.typeCheckFailure),
      members,
      HeapPlan(),
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

  test('an earlier managed argument is live across the next actual materialization', () {
    final accept = FunctionTarget(uri, 'accept', .voidType, [.object, .object]);
    final caller = FunctionTarget(uri, 'caller', .voidType, [
      .integer,
      .floating,
    ]);
    final entry = Block(caller.parameterTypes);
    final call = entry.emit(DirectCall(accept, entry.parameters));
    entry.finish(const Return());
    final body = _adapt(IrFunction(caller, [entry]));
    final boxes = _ops(body).whereType<MaterializeValue>().toList();
    final invoked = _ops(body).whereType<DirectCall>().single;
    final flow = ValueLiveness.source(body, calls: {...boxes, invoked});
    expect(boxes, hasLength(2));
    expect(flow.acrossCalls[boxes.last], contains(boxes.first));
    expect(invoked.inputs, boxes);
    expect(entry.instructions, [call]);
    _selectAdapted(body);
  });

  test(
    'edge conversions stay conditional and retain actual allocation effects',
    () {
      final target = FunctionTarget(uri, 'branch', .integer, [
        .boolean,
        .integer,
      ]);
      final entry = Block(target.parameterTypes),
          taken = Block([ValueType.object]),
          other = Block();
      entry.finish(
        Branch(
          entry.parameters[0],
          Jump(taken, [entry.parameters[1]]),
          Jump(other),
        ),
      );
      taken.finish(const Return(Constant.integer(1)));
      other.finish(const Return(Constant.integer(0)));
      final body = _adapt(IrFunction(target, [entry, taken, other]));
      final branch = body.entry.end as Branch;
      expect(
        branch.ifTrue.target.instructions.whereType<MaterializeValue>(),
        hasLength(1),
      );
      expect(
        branch.ifFalse.target.instructions.whereType<MaterializeValue>(),
        isEmpty,
      );
      final rewritten = FunctionRewrite(body).run();
      expect(_ops(rewritten).whereType<MaterializeValue>(), hasLength(1));
      _selectAdapted(body);
    },
  );

  test('shared source edges keep their explicit conversion operands', () {
    final target = FunctionTarget(uri, 'sharedEdge', .object, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        done = Block([ValueType.object]);
    final edge = Jump(done, [entry.parameters.last]);
    entry.finish(Branch(entry.parameters.first, edge, edge));
    done.finish(Return(done.parameters.single));
    final body = _adapt(IrFunction(target, [entry, done]));
    final branch = body.entry.end as Branch;
    expect(branch.ifTrue.target, isNot(same(branch.ifFalse.target)));
    for (final edge in [branch.ifTrue, branch.ifFalse]) {
      final transfer = edge.target.end as Jump;
      expect(transfer.arguments, [edge.target.instructions.single]);
    }
    _selectAdapted(body);
  });

  test(
    'invoke arguments and outcomes convert under their original handler',
    () {
      final target = FunctionTarget(uri, 'invoke', .object, [.integer]);
      final callee = FunctionTarget(uri, 'callee', .integer, [.object]);
      final entry = Block(target.parameterTypes),
          success = Block([ValueType.object]);
      final failure = Block([
        ValueType.object,
        ValueType.stackTrace,
        ValueType.integer,
      ]);
      final call = DirectCall(callee, entry.parameters);
      entry.finish(
        Invoke(
          call,
          onReturn: Jump(success, [call]),
          onThrow: Jump(failure, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
            entry.parameters.single,
          ]),
        ),
      );
      success.finish(Return(success.parameters.single));
      final failedBox = failure.emit(MaterializeValue(failure.parameters.last));
      failure.emit(KeepAlive(failure.parameters.first));
      failure.emit(KeepAlive(failure.parameters[1]));
      failure.finish(Return(failedBox));
      final body = _adapt(IrFunction(target, [entry, success, failure]));
      final first = body.entry.end as Invoke;
      expect(first.operation, isA<MaterializeValue>());
      final invoked = body.blocks
          .map((b) => b.end)
          .whereType<Invoke>()
          .singleWhere((end) => end.operation is DirectCall);
      expect(invoked.onThrow.target, same(first.onThrow.target));
      final materializations = _ops(body)
          .whereType<MaterializeValue>()
          .toList();
      expect(materializations, hasLength(3));
      final flow = ValueLiveness.source(body, calls: materializations.toSet());
      final caught = body.blocks.singleWhere(
        (b) =>
            b.parameters.length == 3 &&
            b.instructions.any((op) => op is MaterializeValue),
      );
      final finalBox = caught.instructions.whereType<MaterializeValue>().single;
      expect(
        flow.acrossCalls[finalBox],
        containsAll(caught.parameters.take(2)),
      );
      _selectAdapted(body);
    },
  );

  test('missing allocation scope on an unwind edge is explicitly rejected', () {
    final target = FunctionTarget(uri, 'ignored', .object, [.integer]);
    final callee = FunctionTarget(uri, 'callee', .voidType, [.object]);
    final entry = Block(target.parameterTypes);
    final done = Block()..finish(const Return(Constant.string('ok')));
    final failed = Block([ValueType.object])
      ..finish(Return(const Constant.nullValue()));
    final call = DirectCall(callee, entry.parameters);
    entry.finish(
      Invoke(
        call,
        onReturn: Jump(done),
        onThrow: Jump(failed, entry.parameters),
      ),
    );
    expect(
      () => _adapt(IrFunction(target, [entry, done, failed])),
      throwsStateError,
    );
  });

  test('unrecorded exceptions cannot bypass semantic normalization', () {
    final target = FunctionTarget(uri, 'unrecorded', .voidType, [.object]);
    final source = Block(target.parameterTypes);
    source.finish(Throw(source.parameters.single));
    expect(
      () => FunctionRepresentation(
        IrFunction(target, [source]),
        layouts,
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        members,
        HeapPlan(),
      ),
      throwsStateError,
    );
  });

  test('materializing a thrown scalar keeps its existing trace alive', () {
    final target = FunctionTarget(uri, 'rethrow', .voidType, [
      .integer,
      .stackTrace,
    ]);
    final entry = Block(target.parameterTypes);
    entry.finish(Throw.recorded(entry.parameters.first, entry.parameters.last));
    final body = _adapt(IrFunction(target, [entry]));
    final box = _ops(body).whereType<MaterializeValue>().single;
    final flow = ValueLiveness.source(body, calls: {box});
    final end = body.entry.end as Throw;
    expect(end.exception, same(box));
    expect(end.stackTrace, same(body.entry.parameters.last));
    expect(flow.acrossCalls[box], {body.entry.parameters.last});
    expect(entry.instructions, isEmpty);
    _selectAdapted(body);
  });
}

Iterable<Instruction> _ops(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

IrFunction _adapt(
  IrFunction function, {
  Iterable<IrClass> classes = const [],
  Iterable<IrFunction> companions = const [],
}) {
  final program = IrProgram(classes, [function, ...companions]);
  return RepresentationLowering()
          .lower(program, [function.target])
          .implementationOf(function.target)
      as IrFunction;
}

FunctionRepresentation _selectAdapted(
  IrFunction function, {
  Iterable<IrClass> classes = const [],
  Iterable<IrFunction> companions = const [],
}) {
  var program = IrProgram(classes, [
    function,
    ...companions,
  ], executionShapes: ExecutionShapes.defaults);
  program = AllocationLowering(heapRuntime).lower(program, [function.target]);
  final lowered = program.implementationOf(function.target) as IrFunction;
  final layout = ProgramLayout(
    program.classes,
    executionShapes: program.executionShapes,
    typeRuntime: heapRuntime.types,
    nativeLayout: NativeLayout(const Target(.linux, .arm64)),
  );
  return FunctionRepresentation(
    lowered,
    layout,
    CheckedCasts(failure: heapRuntime.typeCheckFailure),
    MemberCalls(program, reachableDefinitions(program, [function.target])),
    HeapPlan(runtime: heapRuntime),
  );
}
