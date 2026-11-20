import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/codegen.dart'
    show
        MemberEntryLowering,
        RepresentationLowering,
        AllocationLowering,
        CallableLowering,
        CallableImplementations,
        TypeImplementations;
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/cell_lowering.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/src/codegen/function_allocation.dart';
import 'package:dartc/src/codegen/function_emitter.dart';
import 'package:dartc/src/codegen/function_selection.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/program_selection.dart';
import 'package:dartc/src/codegen/selected_function.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';
import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:scalar-representation');
  const target = Target(.linux, .arm64);
  setUpAll(prepareRuntime);

  ProgramLayout layouts([Iterable<IrClass> classes = const []]) =>
      ProgramLayout(
        classes,
        nativeLayout: NativeLayout(target),
        typeRuntime: heapRuntime.types,
      );

  SelectedFunction represent(IrFunction function, ProgramLayout layout) {
    var program = IrProgram([], [
      function,
    ], executionShapes: layout.executionShapes);
    program = RepresentationLowering().lower(program, [function.target]);
    program = AllocationLowering(heapRuntime).lower(program, [function.target]);
    final source = program.implementationOf(function.target) as IrFunction;
    final selection = ProgramSelection(
      layout,
      HeapPlan(runtime: heapRuntime),
      CheckedCasts(failure: heapRuntime.typeCheckFailure),
      MemberCalls(program, {function.target}),
      layout.instances,
    )..include(source);
    return selection.functions[function.target]!;
  }

  test('lowered member frames retain their asynchronous continuation', () {
    final uri = Uri.parse('memory:continuation');
    for (final asynchronous in [true, false]) {
      final owner = ClassType(
        uri,
        'Receiver',
        interfaces: [if (asynchronous) heapRuntime.stackContext!],
      );
      final member = FunctionTarget(
        uri,
        'run',
        .voidType,
        [],
        owner: owner,
        kind: .method,
      );
      final inspect = FunctionTarget(uri, 'inspect', .voidType, []);
      final methodEntry = Block(member.parameterTypes);
      final inspectCall = methodEntry.emit(DirectCall(inspect, []));
      methodEntry.finish(const Return());
      final method = IrFunction(member, [methodEntry]);
      final root = FunctionTarget(uri, 'root', .voidType, [owner]);
      final entry = Block(root.parameterTypes);
      entry.emit(InstanceCall(member, entry.parameters.single, const []));
      entry.finish(const Return());
      final source = IrProgram(
        [
          IrClass(owner, [], members: [member]),
        ],
        [
          method,
          IrFunction(root, [entry]),
        ],
        externals: [IrExternal(inspect)],
      );
      final bound = MemberEntryLowering(TypeImplementations())
          .run(ProgramFlow(source, const [], openEntries: [root]).facts);
      final layout = layouts(bound.classes);
      final selection = ProgramSelection(
        layout,
        HeapPlan(runtime: heapRuntime),
        CheckedCasts(failure: heapRuntime.typeCheckFailure),
        MemberCalls(bound, {...bound.functions.map((f) => f.target), inspect}),
        layout.instances,
      );
      final implementation = bound.functions.singleWhere(
        (f) => f.target.executionSource == member,
      );
      selection.include(implementation);
      final selected = selection.functions[implementation.target]!;
      final allocation = FunctionAllocation(
        FunctionSelection(selected, _Constraints()),
      );
      final roots = allocation.safepoints[inspectCall]!;
      if (asynchronous) {
        expect(selected.stackContext, same(selected.entryParameters.first));
        expect(allocation.contextOffset, isNotNull);
        expect(roots.offsets, contains(allocation.contextOffset));
      } else {
        expect(selected.stackContext, isNull);
        expect(allocation.contextOffset, isNull);
      }
    }
  });

  for (final (name, scalar, constant, register, word)
      in <(String, ValueType, Constant, CpuRegister, int)>[
        ('int', .integer, const Constant.integer(-73), Register.x0, -73),
        (
          'double',
          .floating,
          const Constant.floating(-0.0),
          FloatRegister.d0,
          -0x8000000000000000,
        ),
        ('bool', .boolean, const Constant.boolean(true), Register.x0, 1),
      ]) {
    test('$name equality helpers use a closed scalar signature', () {
      final t = TypeParameterType('T')..initializeBound(scalar);
      for (final type in <ValueType>[
        t,
        PromotedTypeParameterType(
          TypeParameterType('P')..initializeBound(.object.nullable),
          scalar,
        ),
        InstantiatedPromotionType(ValueType.object, scalar),
      ]) {
        final members = MemberCalls(IrProgram([], []), {});
        final target = members.builtin(type, hash: false);
        final body = members.functions.single;
        final runner = IrInterpreter(IrProgram([], [body]), {});
        expect(target.parameterTypes.first, scalar);
        final Object input = scalar == .boolean
            ? true
            : scalar == .integer
            ? 42
            : 42.0;
        for (final other in <Object?>[null, true, false, 42, 42.0, 43, '42']) {
          expect(runner.run(body, [input, other]), input == other);
        }
        if (scalar == .floating) {
          expect(runner.run(body, [double.nan, double.nan]), isFalse);
        }
      }
      final function = FunctionTarget(
        uri,
        'equal',
        .boolean,
        [t, .object],
        typeParameters: [t],
      );
      final entry = Block(function.parameterTypes);
      final equal = entry.emit(
        Equals(entry.parameters[0], entry.parameters[1]),
      );
      entry.finish(Return(equal));
      final body = represent(IrFunction(function, [entry]), layouts());
      final actual = body.invocations.keys.whereType<Equals>().single;
      expect(body.invocations[actual]!.parameterTypes.first, scalar);
      expect(
        _operations(body.sourceFunction!).whereType<MaterializedValue>(),
        isEmpty,
      );
    });

    for (final boundKind in ['direct', 'chained', 'promoted']) {
      test(
        '$boundKind $name keeps scalar calls and managed roots distinct',
        () {
          final u = TypeParameterType('U')..initializeBound(scalar);
          final t = TypeParameterType('T')
            ..initializeBound(boundKind == 'chained' ? u : scalar);
          final ValueType valueType = boundKind == 'promoted'
              ? PromotedTypeParameterType(
                  TypeParameterType('P')..initializeBound(.object.nullable),
                  scalar,
                )
              : t;
          final typeParameters = boundKind == 'promoted'
              ? [(valueType as PromotedTypeParameterType).parameter]
              : [if (boundKind == 'chained') u, t];
          final function = FunctionTarget(uri, 'retain', valueType, [
            valueType,
            .object,
          ], typeParameters: typeParameters);
          final poll = FunctionTarget(uri, 'poll', .voidType, []);
          final entry = Block(function.parameterTypes);
          entry.emit(DirectCall(poll, []));
          entry.emit(KeepAlive(entry.parameters[1]));
          entry.finish(Return(entry.parameters.first));
          final body = represent(IrFunction(function, [entry]), layouts());
          final selection = FunctionSelection(body, _Constraints());

          expect(entry.parameters.first.type, same(valueType));
          expect(function.returnType, same(valueType));
          expect(selection.entry.parameters.first.registers, [register]);
          expect(selection.entry.resultRegister, register);
          final call = body.invocations.keys
              .whereType<DirectCall>()
              .singleWhere((call) => call.target == poll);
          expect(
            _operations(body.sourceFunction!).whereType<MaterializedValue>(),
            isEmpty,
          );
          expect(
            selection.liveReferences[call],
            contains(body.entry.parameters[1]),
          );
          expect(
            selection.liveReferences[call],
            isNot(contains(body.entry.parameters.first)),
          );
        },
      );
    }

    test('$name generic field constants match the emitted GC descriptor', () {
      final t = TypeParameterType('T')..initializeBound(scalar);
      final owner = ClassType(uri, 'Stored$name', typeParameters: [t]);
      final field = InstanceField(owner, 'value', t, isFinal: true);
      final layout = layouts([
        IrClass(owner, [field]),
      ]);
      final data = ConstantData(layout, 0);
      final symbol = data.addressOf(
        ObjectConstant(owner.instantiate([scalar]), {field: constant}),
      );
      final bytes = ByteData.sublistView(data.finish().bytes);
      final offset = data.symbols[symbol].offset + layout.fieldOffset(field);

      expect(field.type, same(t));
      expect(bytes.getInt64(offset, Endian.little), word);
      expect(data.relocations.where((item) => item.offset == offset), isEmpty);
      expect(layout.storageOf(owner).layout.referenceOffsets, [
        ObjectHeader.typeOffset,
      ]);
    });

    test('$name call substitution uses the callee scalar contract', () {
      final t = TypeParameterType('T')..initializeBound(scalar);
      final relay = FunctionTarget(uri, 'relay', t, [t], typeParameters: [t]);
      final caller = FunctionTarget(uri, 'caller', scalar, [scalar]);
      final entry = Block(caller.parameterTypes);
      final call = entry.emit(
        DirectCall(relay, entry.parameters, typeArguments: [scalar]),
      );
      entry.finish(Return(call));
      final body = represent(IrFunction(caller, [entry]), layouts());
      final selection = FunctionSelection(body, _Constraints());

      final actual = body.invocations.keys.whereType<DirectCall>().singleWhere(
        (call) => call.target == relay,
      );
      expect(
        _operations(body.sourceFunction!).whereType<MaterializedValue>(),
        isEmpty,
      );
      expect(body.inputsOf(actual).first, same(body.entry.parameters.single));
      expect(selection.calls[actual]!.layout.parameters.first.registers, [
        register,
      ]);
      expect(selection.calls[actual]!.layout.resultRegister, register);
      expect(relay.signature.parameters.single, same(t));
      expect(call.type, scalar);
    });

    test(
      '$name captured cells have scalar payload and reference ownership',
      () {
        final t = TypeParameterType('T')..initializeBound(scalar);
        final outer = FunctionTarget(
          uri,
          'capture',
          FunctionType(t, []),
          [t],
          typeParameters: [t],
        );
        final cellType = CellType(t);
        final closure = FunctionTarget(
          uri,
          'read',
          t,
          [],
          kind: .closure,
          enclosing: outer,
          sourceOffset: 1,
          captures: [cellType, t],
        );
        final entry = Block(outer.parameterTypes);
        final cell = entry.emit(NewCell(cellType, entry.parameters.single));
        entry.finish(
          Return(
            entry.emit(MakeClosure(closure, [cell, entry.parameters.single])),
          ),
        );
        final read = Block(closure.parameterTypes);
        read.finish(Return(read.emit(ReadCell(read.parameters[1]))));
        final functions = [
          IrFunction(outer, [entry]),
          IrFunction(closure, [read]),
        ];
        final failure = FunctionTarget(null, 'bindingFailure', .never, [.string]);
        final failed = Block(failure.parameterTypes)
          ..finish(Throw.recorded(const Constant.string('unbound cell'), null));
        var program = IrProgram([], [...functions, IrFunction(failure, [failed])]);
        ProgramFlowFacts analyze() => ProgramFlow(
          program,
          const [],
          openEntries: [outer],
          escapingReturns: [outer],
        ).facts;
        program = CellLowering(failure: failure).run(analyze());
        final implementations = CallableImplementations(
          types: TypeImplementations(runtime: heapRuntime.types),
        );
        program = CallableLowering(implementations).run(analyze());
        final storage = implementations.storage;
        final layout = ProgramLayout(
          program.classes,
          closureStorage: storage,
          executionShapes: program.executionShapes,
          nativeLayout: NativeLayout(target),
          typeRuntime: heapRuntime.types,
        );
        final cellShape = program.classes
            .map((c) => c.cellStorage)
            .nonNulls
            .single;
        final closureShape = storage.closures[closure]!;
        final closureLayout = layout.storageOf(closureShape.type);

        expect(closure.captures, [cellType, t]);
        expect(cell.type, same(cellType));
        expect(layout.storageOf(cellShape.type).layout.referenceOffsets, [
          ObjectHeader.typeOffset,
        ]);
        expect(closureLayout.layout.referenceOffsets, [
          ObjectHeader.typeOffset,
          closureLayout.offsetOf(closureShape.storage.environment),
          closureLayout.offsetOf(closureShape.storage.anchor),
          closureLayout.offsetOf(closureShape.storage.arguments),
          closureLayout.offsetOf(closureShape.captures.first),
          ...closureShape.environment.map(closureLayout.offsetOf),
        ]);
        expect(cellShape.value.type, scalar);
        expect(closureShape.captures.last.type, scalar);
      },
    );

    test('$name materializes at its actual reference result boundary', () {
      final t = TypeParameterType('T')..initializeBound(scalar);
      final function = FunctionTarget(
        uri,
        'observe',
        .object,
        [t],
        typeParameters: [t],
      );
      final poll = FunctionTarget(uri, 'poll', .voidType, []);
      final entry = Block(function.parameterTypes);
      final widened = entry.emit(TypeView(entry.parameters.single, .object));
      entry.emit(DirectCall(poll, []));
      entry.finish(Return(widened));
      final source = IrFunction(function, [entry]);
      final layout = layouts();
      final body = represent(source, layout);
      final selected = FunctionSelection(body, _Constraints());

      expect(entry.parameters.single.type, same(t));
      expect(widened.type, ValueType.object);
      final operations = _operations(body.sourceFunction!).toList();
      final materialized = operations.whereType<MaterializedValue>().single;
      final call = operations.whereType<DirectCall>().singleWhere(
        (call) => call.target == poll,
      );
      final allocation = operations.whereType<DirectCall>().singleWhere(
        (call) => call.target == heapRuntime.allocate,
      );
      expect(materialized.type, same(t));
      expect(body.shapeOf(materialized), ExecutionShape.reference);
      expect(
        operations.indexOf(call),
        lessThan(operations.indexOf(allocation)),
      );
      expect(selected.liveReferences[call], isNot(contains(materialized)));
      expect(
        selected.liveReferences[call],
        isNot(contains(body.entry.parameters.single)),
      );
    });
  }

  for (final bound in <ValueType>[
    ValueType.integer.nullable,
    ValueType.floating.nullable,
    ValueType.boolean.nullable,
    ValueType.number,
    ValueType.object.nullable,
  ]) {
    test('${bound.dartName} does not erase null or mixed representations', () {
      final t = TypeParameterType('T')..initializeBound(bound);
      final function = FunctionTarget(
        uri,
        'retainReference',
        t,
        [t],
        typeParameters: [t],
      );
      final entry = Block(function.parameterTypes);
      final poll = FunctionTarget(uri, 'poll', .voidType, []);
      entry.emit(DirectCall(poll, []));
      entry.finish(Return(entry.parameters.single));
      final body = represent(IrFunction(function, [entry]), layouts());
      final selection = FunctionSelection(body, _Constraints());
      final call = body.invocations.keys.whereType<DirectCall>().singleWhere(
        (call) => call.target == poll,
      );
      expect(
        selection.liveReferences[call],
        contains(body.entry.parameters.single),
      );

      final owner = ClassType(uri, 'Reference', typeParameters: [t]);
      final field = InstanceField(owner, 'value', t);
      final layout = layouts([
        IrClass(owner, [field]),
      ]);
      expect(layout.storageOf(owner).layout.referenceOffsets, [
        ObjectHeader.typeOffset,
        layout.fieldOffset(field),
      ]);
    });
  }
}

Iterable<Instruction> _operations(IrFunction function) sync* {
  for (final block in function.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

/// Selection consumes ABI constraints without emitting or executing native code.
final class _Constraints() implements FunctionEmitter<CpuRegister> {
  @override
  final convention = Arm64Abi(const Target(.linux, .arm64));
  @override
  final allocatableRegisters = <CpuRegister>[
    Register.x0,
    Register.x1,
    Register.x2,
    Register.x3,
    FloatRegister.d0,
    FloatRegister.d1,
    FloatRegister.d2,
    FloatRegister.d3,
  ];
  @override
  RegisterBank bank(CpuRegister register) =>
      register is Register ? .general : .floating;
  @override
  CpuRegister get exceptionRegister => Register.x0;
  @override
  CpuRegister get traceRegister => Register.x1;
  @override
  CpuRegister get failureRegister => Register.x16;
  @override
  bool get negationNeedsTemporary => false;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
