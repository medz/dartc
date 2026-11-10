import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'heap_functions.dart';
import 'function_emitter.dart';
import 'program_layout.dart';
import 'frame_lookup.dart';
import 'type_values.dart';

/// Generates allocation wrappers with precise roots and optional initialization.
final class HeapPlan(
  IrProgram program,
  Set<FunctionTarget> selected,
  ProgramLayout layouts,
  FrameLookup frames,
) {
  final constructors = <Construct, FunctionTarget>{};
  final _factories =
      <FunctionTarget, ({FunctionTarget? initializer, ClassType type})>{};
  final _boxes = <ValueType, FunctionTarget>{};
  final _initializers = <FunctionTarget, FunctionTarget>{};
  final heap = HeapFunctions(frames);

  bool get isEmpty => _factories.isEmpty;
  List<IrFunction> get functions => heap.functions;

  FunctionTarget box(ValueType type) => _boxes.putIfAbsent(type, () {
    final target = FunctionTarget(
      Uri.parse('dartc:heap'),
      'box${_boxes.length}',
      .object,
      [type],
    );
    _factories[target] = (initializer: null, type: type as ClassType);
    return target;
  });

  void retain(Set<FunctionTarget> calls) =>
      _factories.removeWhere((target, _) => !calls.contains(target));

  Set<FunctionTarget> get primitives => {
    heap.map,
    heap.unmap,
    heap.invalid,
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
  ) {
    if (target == heap.map) return emitter.mapMemory();
    if (target == heap.unmap) return emitter.unmapMemory();
    if (target == heap.invalid) {
      emitter.abort(71);
      return emitter.finish();
    }
    final (:initializer, :type) = _factories[target]!;
    CallLayout<R> classify(FunctionTarget function) =>
        emitter.convention.classify(
          NativeSignature.types(
            layouts.callType(function.returnType),
            function.parameterTypes.map(layouts.callType),
          ),
        );
    final source = classify(target),
        destination = initializer == null ? null : classify(initializer);
    final parameterTypes = target.parameterTypes;
    final allocation = emitter.convention.classify(
      NativeSignature(Int64, List.filled(4, Int64)),
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
          r != allocation.result &&
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
    call(emitter.call(), heap.allocate);
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
        .emit(emitter.failureRegister, allocation.result!, arguments[3]);
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
      allocation.result!,
      offset: ObjectLayout.typeOffset,
      bytes: 8,
    );
    emitter.loadImmediate(emitter.failureRegister, 0);
    if (initializer == null) {
      final value = scratch(type);
      emitter.loadStack(value, frame.localOffset);
      emitter.storeMemory(
        value,
        allocation.result!,
        offset: ObjectLayout.fieldsOffset,
        bytes: 8,
      );
      // The payload scratch may also carry the call failure flag.
      emitter.loadImmediate(emitter.failureRegister, 0);
      emitter.epilogue(frame);
      return emitter.finish();
    }
    emitter.storeStack(allocation.result!, objectOffset);

    int offsetOf(int i) =>
        i == 0 ? objectOffset : frame.localOffset + (i - 1) * 8;
    for (final (i, location) in destination!.parameters.indexed) {
      if (location case StackArgument(:final offset)) {
        final register = scratch(initializer.parameterTypes[i]);
        emitter.loadStack(register, offsetOf(i));
        emitter.storeStack(register, offset);
      }
    }
    for (final (i, location) in destination.parameters.indexed) {
      if (location case RegisterArgument(:final register)) {
        emitter.loadStack(register, offsetOf(i));
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
    emitter.loadStack(source.result!, objectOffset);
    emitter.epilogue(frame);
    return emitter.finish();
  }

  this {
    include([
      for (final target in selected)
        if (program.implementationOf(target) case final IrFunction body) body,
    ], layouts);
  }

  void include(Iterable<IrFunction> functions, ProgramLayout layouts) {
    final uri = Uri.parse('dartc:heap');
    for (final body in functions) {
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ].whereType<Construct>()) {
          final initializer = operation.initializer;
          constructors[operation] = _initializers.putIfAbsent(initializer, () {
            final target = FunctionTarget(
              uri,
              'construct${_initializers.length}',
              .object,
              [
                for (final parameter in initializer.signature.parameters)
                  layouts.representation(parameter) == .reference
                      ? ValueType.object.nullable
                      : parameter,
                TypeValues.type,
              ],
            );
            _factories[target] = (
              initializer: initializer,
              type: initializer.owner!,
            );
            return target;
          });
        }
      }
    }
  }
}
