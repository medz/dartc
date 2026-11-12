import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';
import 'program_layout.dart';
import 'heap_runtime.dart';

/// Generates allocation wrappers with precise roots and optional initialization.
final class HeapPlan({final HeapRuntime? runtime}) {
  final _factories =
      <FunctionTarget, ({FunctionTarget? initializer, ClassType type})>{};
  final _boxes = <ValueType, FunctionTarget>{};
  final _initializers = <FunctionTarget, FunctionTarget>{};
  final _payloads = <ClassType, FunctionTarget>{};
  static final _invalid = FunctionTarget(null, 'invalid', .never, []);

  FunctionTarget get invalid =>
      runtime?.primitives.entries
          .where((entry) => entry.value == .fail)
          .firstOrNull
          ?.key ??
      _invalid;
  FunctionTarget get allocate => _runtime.allocate;
  FunctionTarget get release => _runtime.release;
  FunctionTarget get runEvents => _runtime.runEvents;
  FunctionTarget get eventAccess => _runtime.eventAccess;
  HeapRuntime get _runtime =>
      runtime ??
      (throw ArgumentError(
        'Managed allocation requires a Dart runtime program.',
      ));

  bool allocates(Iterable<FunctionTarget> calls) =>
      calls.any(_factories.containsKey);

  /// Source initializers called by the retained allocation wrappers.
  Iterable<FunctionTarget> get initializers =>
      _factories.values.map((entry) => entry.initializer).nonNulls;

  FunctionTarget box(ValueType type) => _boxes.putIfAbsent(type, () {
    final target = FunctionTarget(null, 'box${_boxes.length}', .object, [type]);
    _factories[target] = (initializer: null, type: type as ClassType);
    return target;
  });

  /// Allocates zeroed inline bytes after a class's fixed fields.
  FunctionTarget allocatePayload(ClassType type) =>
      _payloads.putIfAbsent(type, () {
        final target = FunctionTarget(
          null,
          'payload${_payloads.length}',
          type,
          [.integer],
        );
        _factories[target] = (initializer: null, type: type);
        return target;
      });

  void retain(Set<FunctionTarget> calls) =>
      _factories.removeWhere((target, _) => !calls.contains(target));

  Set<FunctionTarget> get primitives => {
    ...?runtime?.primitives.keys,
    invalid,
    ..._factories.keys,
  };

  Uint8List emit<R extends Object>(
    FunctionTarget target,
    FunctionEmitter<R> emitter,
    ProgramLayout layouts,
    void Function(Fixup, FunctionTarget) call,
    void Function(Fixup, ClassType) descriptor,
    void Function(Fixup, Constant) constant,
    void Function(int, StackRoots) safepoint,
    void Function(Fixup, int) codeAddress,
    void Function(Fixup) systemClock,
  ) {
    if (runtime?.primitives[target] == MemoryPrimitive.map) {
      return emitter.mapMemory();
    }
    if (runtime?.primitives[target] == MemoryPrimitive.unmap) {
      return emitter.unmapMemory();
    }
    if (runtime?.primitives[target] == MemoryPrimitive.writeBytes) {
      return emitter.writeBytes();
    }
    if (runtime?.primitives[target] == MemoryPrimitive.clock) {
      return emitter.clock(systemClock);
    }
    if (runtime?.primitives[target] == MemoryPrimitive.sleep) {
      return emitter.sleep();
    }
    if (target == invalid) {
      emitter.abort(71);
      return emitter.finish();
    }
    if (runtime?.primitives[target] == MemoryPrimitive.context) {
      final result = emitter.convention
          .classify(NativeSignature(Int64, []))
          .resultRegister!;
      emitter.move(result, emitter.heapRegister);
      emitter.loadImmediate(emitter.failureRegister, 0);
      emitter.ret();
      return emitter.finish();
    }
    final (:initializer, :type) = _factories[target]!;
    CallLayout<R> classify(FunctionTarget function) =>
        emitter.convention.classify(
          NativeSignature.types(
            layouts.callType(function.returnType),
            layouts.entryTypes(function).map(layouts.callType),
          ),
        );
    final source = classify(target),
        destination = initializer == null ? null : classify(initializer);
    final parameterTypes = target.parameterTypes;
    final allocation = emitter.convention.classify(
      NativeSignature(Int64, List.filled(5, Int64)),
    );
    final arguments = allocation.parameters
        .map((p) => (p as RegisterArgument<R>).register)
        .toList();
    final frame = emitter.convention.frameLayout(
      localBytes: (parameterTypes.length + (initializer == null ? 0 : 1)) * 8,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: destination?.stackBytes ?? 0,
    );
    final objectOffset = frame.localOffset + parameterTypes.length * 8;
    R scratch(ValueType type) => emitter.allocatableRegisters.lastWhere(
      (r) =>
          r != allocation.resultRegister &&
          emitter.bank(r) ==
              (layouts.representation(type) == .floating
                  ? RegisterBank.floating
                  : RegisterBank.general),
    );
    emitter.prologue(frame);
    for (final (i, location) in source.parameters.indexed) {
      if (location case RegisterArgument(:final register)) {
        emitter.storeStack(register, frame.localOffset + i * 8);
      }
    }
    for (final (i, location) in source.parameters.indexed) {
      if (location case StackArgument(:final offset)) {
        final register = scratch(parameterTypes[i]);
        emitter.loadStack(register, frame.incomingStackOffset + offset);
        emitter.storeStack(register, frame.localOffset + i * 8);
      }
    }
    emitter.move(arguments[0], emitter.heapRegister);
    emitter.address(arguments[1], (fixup) => descriptor(fixup, type));
    emitter.stackAddress(arguments[2], 0);
    final returnAddress = <Fixup>[];
    emitter.address(arguments[3], returnAddress.add);
    final payload = _payloads[type] == target;
    if (payload) {
      emitter.loadStack(arguments[4], frame.localOffset);
    } else {
      emitter.loadImmediate(arguments[4], 0);
    }
    call(emitter.call(), allocate);
    final position = emitter.position;
    for (final fixup in returnAddress) {
      codeAddress(fixup, position);
    }
    safepoint(
      position,
      StackRoots(frame.incomingStackOffset, frame.returnAddressOffset, [
        for (final (i, type) in parameterTypes.indexed)
          if (layouts.isReference(type)) frame.localOffset + i * 8,
      ]),
    );
    emitter.loadImmediate(arguments[3], 0);
    emitter
        .comparison(.equal)
        .emit(
          emitter.failureRegister,
          allocation.resultRegister!,
          arguments[3],
        );
    final allocated = emitter.label();
    emitter.jumpIfZero(emitter.failureRegister, allocated);
    emitter.epilogue(frame);
    emitter.bind(allocated);
    final runtimeType = scratch(ValueType.typeType);
    if (initializer == null) {
      emitter.address(
        runtimeType,
        (fixup) => constant(fixup, layouts.types.constant(type)),
      );
    } else {
      emitter.loadStack(
        runtimeType,
        frame.localOffset + (parameterTypes.length - 1) * 8,
      );
    }
    emitter.storeMemory(
      runtimeType,
      allocation.resultRegister!,
      offset: ObjectHeader.typeOffset,
      bytes: 8,
    );
    emitter.loadImmediate(emitter.failureRegister, 0);
    if (initializer == null) {
      if (payload) {
        emitter.epilogue(frame);
        return emitter.finish();
      }
      final value = scratch(type);
      emitter.loadStack(value, frame.localOffset);
      emitter.storeMemory(
        value,
        allocation.resultRegister!,
        offset: ObjectHeader.fieldsOffset,
        bytes: 8,
      );
      // The payload scratch may also carry the call failure flag.
      emitter.loadImmediate(emitter.failureRegister, 0);
      emitter.epilogue(frame);
      return emitter.finish();
    }
    emitter.storeStack(allocation.resultRegister!, objectOffset);

    void loadArgument(int i, R register) {
      emitter.loadStack(
        register,
        i == 0 ? objectOffset : frame.localOffset + (i - 1) * 8,
      );
      if (layouts.pointerParameters.contains(initializer, i)) {
        emitter.loadMemory(
          register,
          register,
          offset: layouts.fieldOffset(layouts.pointers.address),
          bytes: 8,
          signed: false,
        );
      }
    }

    for (final (i, location) in destination!.parameters.indexed) {
      if (location case StackArgument(:final offset)) {
        final register = scratch(initializer.parameterTypes[i]);
        loadArgument(i, register);
        emitter.storeStack(register, offset);
      }
    }
    for (final (i, location) in destination.parameters.indexed) {
      if (location case RegisterArgument(:final register)) {
        loadArgument(i, register);
      }
    }
    call(emitter.call(), initializer);
    safepoint(
      emitter.position,
      StackRoots(frame.incomingStackOffset, frame.returnAddressOffset, [
        objectOffset,
      ]),
    );
    final initialized = emitter.label();
    emitter.jumpIfZero(emitter.failureRegister, initialized);
    emitter.epilogue(frame);
    emitter.bind(initialized);
    emitter.loadStack(source.resultRegister!, objectOffset);
    emitter.epilogue(frame);
    return emitter.finish();
  }

  FunctionTarget constructorFor(
    FunctionTarget initializer,
    ProgramLayout layouts,
  ) => _initializers.putIfAbsent(initializer, () {
    final target = FunctionTarget(
      null,
      'construct${_initializers.length}',
      .object,
      [
        for (final parameter in initializer.signature.parameters)
          layouts.representation(parameter) == .reference
              ? ValueType.object.nullable
              : parameter,
        TypeMetadata.type,
      ],
    );
    _factories[target] = (initializer: initializer, type: initializer.owner!);
    return target;
  });
}
