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
      case .instantiateClosure:
        if (target.kind != .function ||
            target.typeParameters.isNotEmpty ||
            target.signature.optionalPositional != 0 ||
            target.signature.named.isNotEmpty ||
            args.length != 2 ||
            target.returnType != ValueType.function ||
            args[1].type is! ClassType) {
          throw ArgumentError('Invalid function instantiation signature.');
        }
        value = block.emit(
          InstantiateFunctionFrom(
            args[0],
            args[1],
            (args[1].type as ClassType).declaration,
          ),
        );
      case .uncheckedCast:
        if (target.kind != .function ||
            target.typeParameters.length != 1 ||
            target.returnType != target.typeParameters.single ||
            target.signature.parameters.length != 1 ||
            target.signature.parameters.single != ValueType.dynamicType ||
            target.signature.optionalPositional != 0 ||
            target.signature.named.isNotEmpty) {
          throw ArgumentError('Invalid unchecked cast signature.');
        }
        value = block.emit(UncheckedCast(args.single, target.returnType));
      case .typeSupertypes:
        continue;
      case .typeView:
        if (target.kind != .function ||
            target.typeParameters.isNotEmpty ||
            target.signature != FunctionType(TypeMetadata.type, [.typeType])) {
          throw ArgumentError('Invalid type view signature.');
        }
        value = block.emit(UncheckedCast(args.single, TypeMetadata.type));
      case .className:
        value = block.emit(ObjectClassName(args.single));
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
      case .entropy:
        primitives[target] = .entropy;
        continue;
      case .clock:
        primitives[target] = .clock;
        continue;
      case .sleep:
        primitives[target] = .sleep;
        continue;
      case .captureStackTrace:
        primitives[target] = .captureStackTrace;
        continue;
      case .read:
        value = block.emit(LoadNative(args.single, .of(Int64)));
      case .readByte:
        value = block.emit(LoadNative(args.single, .of(Uint8)));
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
      case .float32FromBits || .float32Bits:
        value = block.emit(FloatBitCast(args.single, width: 32));
      case .float64FromBits || .float64Bits:
        value = block.emit(FloatBitCast(args.single));
      case .write:
        block.emit(StoreNative(args.first, .of(Int64), args.last));
        value = null;
      case .writeByte:
        block.emit(StoreNative(args.first, .of(Uint8), args.last));
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
      isOutOfMemory = annotations.entries[RuntimeRole.isOutOfMemory],
      release = annotations.entries[RuntimeRole.release],
      runEvents = annotations.entries[RuntimeRole.runEvents],
      eventAccess = annotations.entries[RuntimeRole.events],
      copyBytes = annotations.entries[RuntimeRole.copyBytes],
      captureStackTrace = annotations.entries[RuntimeRole.captureStackTrace],
      recordError = annotations.entries[RuntimeRole.recordError];
  if (allocate == null ||
      isOutOfMemory == null ||
      release == null ||
      runEvents == null ||
      eventAccess == null ||
      copyBytes == null ||
      captureStackTrace == null ||
      recordError == null) {
    throw ArgumentError('Missing runtime entry contract.');
  }
  return HeapRuntime(
    program,
    types: TypeRuntime(
      program,
      annotations.entries,
      annotations.primitives.entries
          .singleWhere((entry) => entry.value == MemoryOperation.typeSupertypes)
          .key,
    ),
    async: switch (annotations.entries) {
      {
        RuntimeRole.asyncCreate: final create,
        RuntimeRole.asyncStart: final start,
        RuntimeRole.asyncAwait: final awaitValue,
        RuntimeRole.asyncReturn: final complete,
      } =>
        AsyncRuntime(create, start, awaitValue, complete),
      _ => null,
    },
    asyncGenerator: switch (annotations.entries) {
      {
        RuntimeRole.asyncStarCreate: final create,
        RuntimeRole.asyncStarStart: final start,
        RuntimeRole.asyncStarYield: final yieldValue,
        RuntimeRole.asyncStarYieldStream: final yieldStream,
        RuntimeRole.asyncStarReturn: final complete,
      } =>
        AsyncGeneratorRuntime(create, start, yieldValue, yieldStream, complete),
      _ => null,
    },
    sync: switch (annotations.entries) {
      {
        RuntimeRole.syncCreate: final create,
        RuntimeRole.syncYield: final yieldValue,
      } =>
        SyncRuntime(create, yieldValue),
      _ => null,
    },
    invocation: annotations.entries[RuntimeRole.invocation],
    dispatchFailure: annotations.entries[RuntimeRole.dispatchFailure],
    exhaustivenessFailure:
        annotations.entries[RuntimeRole.exhaustivenessFailure],
    floatingRemainder: annotations.entries[RuntimeRole.floatingRemainder],
    floatingModulo: annotations.entries[RuntimeRole.floatingModulo],
    allocate: allocate,
    isOutOfMemory: isOutOfMemory,
    release: release,
    runEvents: runEvents,
    eventAccess: eventAccess,
    copyBytes: copyBytes,
    captureStackTrace: captureStackTrace,
    stackContext: annotations.stackContext,
    recordError: recordError,
    primitives: primitives,
    nonAllocating: annotations.nonAllocating,
  );
}
