import 'dart:ffi';

import 'package:dartc/frontend.dart';

import 'package:dartc/runtime/contracts.dart';

import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';

/// Binds the bundled runtime's external memory operations to trusted IR.
HeapRuntime bindRuntime(LoweringResult lowered) {
  var program = lowered.program;
  final annotations = lowered.runtime;
  final bodies = <IrFunction>[];
  final primitives = <FunctionTarget, MemoryPrimitive>{};
  for (final external in program.externals) {
    final target = external.target;
    final operation = annotations.primitives[target];
    if (operation == null) continue;
    final block = Block(target.parameterTypes);
    final args = block.parameters;
    final Value? value;
    switch (operation) {
      case .map:
        primitives[target] = .map;
        continue;
      case .unmap:
        primitives[target] = .unmap;
        continue;
      case .fail:
        primitives[target] = .fail;
        continue;
      case .context:
        primitives[target] = .context;
        continue;
      case .writeBytes:
        primitives[target] = .writeBytes;
        continue;
      case .clock:
        primitives[target] = .clock;
        continue;
      case .sleep:
        primitives[target] = .sleep;
        continue;
      case .read:
        value = block.emit(LoadNative(args.single, .new(Int64)));
      case .readByte:
        value = block.emit(LoadNative(args.single, .new(Uint8)));
      case .allocatePayload:
        value = block.emit(
          NewPayload(target.returnType as ClassType, args.single),
        );
      case .readReference:
        value = block.emit(LoadObjectReference(args[0], args[1]));
      case .writeReference:
        block.emit(StoreObjectReference(args[0], args[1], args[2]));
        value = null;
      case .keepAlive:
        block.emit(KeepAlive(args.single));
        value = null;
      case .write:
        block.emit(StoreNative(args.first, .new(Int64), args.last));
        value = null;
      case .writeByte:
        block.emit(StoreNative(args.first, .new(Uint8), args.last));
        value = null;
      case .addressOf:
        value = block.emit(ReferenceAddress(args.single));
      case .objectAt:
        value = block.emit(
          ReferenceFromAddress(args.single, target.returnType),
        );
    }
    block.finish(Return(value));
    bodies.add(IrFunction(target, [block]));
  }
  final supplied = bodies.map((body) => body.target).toSet();
  program = IrProgram(
    program.classes,
    [...program.functions, ...bodies],
    globals: program.globals,
    externals: program.externals.where(
      (external) => !supplied.contains(external.target),
    ),
  );
  final allocate = annotations.entries[RuntimeRole.allocate],
      release = annotations.entries[RuntimeRole.release],
      runEvents = annotations.entries[RuntimeRole.runEvents],
      eventAccess = annotations.entries[RuntimeRole.events],
      copyBytes = annotations.entries[RuntimeRole.copyBytes];
  if (allocate == null ||
      release == null ||
      runEvents == null ||
      eventAccess == null ||
      copyBytes == null) {
    throw ArgumentError('Missing runtime entry contract.');
  }
  return HeapRuntime(
    program,
    allocate: allocate,
    release: release,
    runEvents: runEvents,
    eventAccess: eventAccess,
    copyBytes: copyBytes,
    primitives: primitives,
    nonAllocating: annotations.nonAllocating,
  );
}
