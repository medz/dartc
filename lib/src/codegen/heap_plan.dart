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

/// Connects construction to allocation and initialization with precise roots.
final class HeapPlan(IrProgram program, Set<FunctionTarget> selected) {
  final constructors = <Construct, FunctionTarget>{};
  final _factories =
      <FunctionTarget, ({FunctionTarget initializer, ClassType type})>{};
  late final HeapFunctions heap;

  bool get isEmpty => constructors.isEmpty;
  List<IrFunction> get functions => heap.functions;

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
    final source = classify(target), destination = classify(initializer);
    final parameterTypes = target.parameterTypes;
    for (final (i, type) in parameterTypes.indexed) {
      if (layouts.representation(type) !=
          layouts.representation(initializer.parameterTypes[i + 1])) {
        throw UnsupportedError('Native constructor argument conversion: $type');
      }
    }
    final allocation = emitter.convention.classify(
      NativeSignature(Int64, List.filled(4, Int64)),
    );
    final arguments = allocation.parameters
        .map((p) => (p as RegisterArgument<R>).register)
        .toList();
    final frame = emitter.convention.frameLayout(
      localBytes: (parameterTypes.length + 1) * 8,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: destination.stackBytes,
    );
    final objectOffset = frame.localOffset + parameterTypes.length * 8;
    R scratch(ValueType type) => emitter.allocatableRegisters.lastWhere(
      (r) =>
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
    emitter.storeStack(allocation.result!, objectOffset);

    int offsetOf(int i) =>
        i == 0 ? objectOffset : frame.localOffset + (i - 1) * 8;
    for (final (i, location) in destination.parameters.indexed) {
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
    final factories = <(FunctionTarget, ClassType), FunctionTarget>{};
    final uri = Uri.parse('dartc:heap');
    for (final target in selected) {
      final body = program.implementationOf(target);
      if (body is! IrFunction) continue;
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ].whereType<Construct>()) {
          final type = operation.instantiatedType,
              initializer = operation.initializer;
          constructors[operation] = factories.putIfAbsent(
            (initializer, type),
            () {
              final target = FunctionTarget(
                uri,
                'construct${factories.length}',
                type,
                initializer.signatureFor(type).parameters,
              );
              _factories[target] = (initializer: initializer, type: type);
              return target;
            },
          );
        }
      }
    }
    if (!isEmpty) {
      heap = HeapFunctions();
    }
  }
}
