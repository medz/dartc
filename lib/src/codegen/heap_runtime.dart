import 'package:dartc/ir.dart';

import 'type_runtime.dart';

/// Machine services available to checked runtime source.
enum MemoryPrimitive() {
  map,
  unmap,
  fail,
  context,
  writeBytes,
  clock,
  sleep,
  captureStackTrace,
}

/// Source program and entry contracts used by managed code generation.
final class HeapRuntime(
  final IrProgram program, {
  required final FunctionTarget allocate,
  required final FunctionTarget release,
  required final FunctionTarget runEvents,
  required final FunctionTarget eventAccess,
  required final FunctionTarget copyBytes,
  required final FunctionTarget captureStackTrace,
  required final FunctionTarget recordError,
  final FunctionTarget? invocation,
  final FunctionTarget? dispatchFailure,
  final FunctionTarget? exhaustivenessFailure,
  final FunctionTarget? floatingRemainder,
  final FunctionTarget? floatingModulo,
  final AsyncRuntime? async,
  final SyncRuntime? sync,
  final AsyncGeneratorRuntime? asyncGenerator,
  final TypeRuntime? types,
  required Map<FunctionTarget, MemoryPrimitive> primitives,
  required Iterable<FunctionTarget> nonAllocating,
}) {
  /// Explicit machine entries; their signatures must match the selected service.
  final Map<FunctionTarget, MemoryPrimitive> primitives = .unmodifiable(
    primitives,
  );

  /// Closures that cannot allocate, throw, or call foreign code after selection.
  final List<FunctionTarget> nonAllocating = .unmodifiable(nonAllocating);

  this {
    if (primitives.values
            .where((service) => service == .captureStackTrace)
            .length !=
        1) {
      throw ArgumentError('Expected one stack capture machine entry.');
    }
    for (final (target, signature) in [
      (allocate, FunctionType(.integer, List.filled(5, ValueType.integer))),
      (release, FunctionType(.voidType, [.integer])),
      (runEvents, FunctionType(.voidType, [.integer])),
      (eventAccess, FunctionType(eventAccess.returnType, [])),
      (copyBytes, FunctionType(.voidType, [.integer, .integer, .integer])),
      (captureStackTrace, FunctionType(.stackTrace, [.integer, .integer])),
      (recordError, FunctionType(.voidType, [.object, .stackTrace])),
      if (invocation case final target?)
        (
          target,
          FunctionType(CoreTypes.invocation, [
            CoreTypes.symbol,
            .integer,
            CoreTypes.listOf(.typeType),
            CoreTypes.listOf(.object.nullable),
            CoreTypes.mapOf(CoreTypes.symbol, .object.nullable),
          ]),
        ),
      if (dispatchFailure case final target?)
        (
          target,
          FunctionType(.object.nullable, [
            .object.nullable,
            CoreTypes.invocation,
          ]),
        ),
      if (exhaustivenessFailure case final target?)
        (target, FunctionType(.never, [])),
      for (final target in [floatingRemainder, floatingModulo].nonNulls)
        (target, FunctionType(.floating, [.floating, .floating])),
    ]) {
      if (target.kind != .function ||
          target.typeParameters.isNotEmpty ||
          target.signature != signature ||
          program.implementationOf(target) is! IrFunction) {
        throw ArgumentError('Invalid runtime entry: ${target.name}');
      }
    }
    for (final MapEntry(key: target, value: service) in primitives.entries) {
      final signature = switch (service) {
        .map => FunctionType(.integer, [.integer]),
        .unmap => FunctionType(.voidType, [.integer, .integer]),
        .fail => FunctionType(.never, []),
        .context => FunctionType(.integer, []),
        .writeBytes => FunctionType(.integer, [.integer, .integer, .integer]),
        .clock => FunctionType(.integer, []),
        .sleep => FunctionType(.voidType, [.integer, .integer]),
        .captureStackTrace => FunctionType(.stackTrace, []),
      };
      if (target.kind != .function ||
          target.typeParameters.isNotEmpty ||
          target.signature != signature ||
          program.implementationOf(target) is! IrExternal) {
        throw ArgumentError('Invalid memory service: ${target.name}');
      }
    }
    for (final target in [
      ?sync?.create,
      ?sync?.yieldValue,
      ?asyncGenerator?.create,
      ?asyncGenerator?.start,
      ?asyncGenerator?.yieldValue,
      ?asyncGenerator?.yieldStream,
      ?asyncGenerator?.complete,
    ]) {
      if (program.implementationOf(target) is! IrFunction) {
        throw ArgumentError(
          'Generator runtime entry requires a Dart body: ${target.name}',
        );
      }
    }
    if (async case final entries?) {
      for (final target in [
        entries.create,
        entries.start,
        entries.awaitValue,
        entries.complete,
      ]) {
        if (program.implementationOf(target) is! IrFunction) {
          throw ArgumentError(
            'Async runtime entry requires a Dart body: ${target.name}',
          );
        }
      }
    }
  }
}

/// Ordinary Dart entries for a future and its suspension callbacks.
final class AsyncRuntime(
  final FunctionTarget create,
  final FunctionTarget start,
  final FunctionTarget awaitValue,
  final FunctionTarget complete,
) {
  static final callback = FunctionType(.voidType, [
    .object.nullable,
    .object.nullable,
    .stackTrace.nullable,
  ]);
  this {
    for (final target in [create, start, awaitValue]) {
      if (target.kind != .function || target.typeParameters.length != 1) {
        throw ArgumentError('Invalid async entry: ${target.name}');
      }
      final t = target.typeParameters.single;
      final signature = target == create
          ? FunctionType(.object, [callback], typeParameters: [t])
          : target == start
          ? FunctionType(
              ValueType.future.instantiate([t]),
              [.object],
              typeParameters: [t],
            )
          : FunctionType(
              .voidType,
              [.object, .object.nullable],
              typeParameters: [t],
            );
      if (target.signature != signature) {
        throw ArgumentError('Invalid async entry signature: ${target.name}');
      }
    }
    if (complete.kind != .function ||
        complete.signature !=
            FunctionType(.voidType, [.object, .object.nullable])) {
      throw ArgumentError('Invalid async completion entry: ${complete.name}');
    }
  }
}

/// Ordinary Dart entries for independent synchronous generator iterations.
final class SyncRuntime(
  final FunctionTarget create,
  final FunctionTarget yieldValue,
) {
  static final callback = FunctionType(.boolean, [.object]);
  static final factory = FunctionType(callback, []);

  this {
    if (create.kind != .function || create.typeParameters.length != 1) {
      throw ArgumentError('Invalid generator entry: ${create.name}');
    }
    final t = create.typeParameters.single;
    if (create.signature !=
            FunctionType(
              CoreTypes.iterableOf(t),
              [factory],
              typeParameters: [t],
            ) ||
        yieldValue.kind != .function ||
        yieldValue.signature !=
            FunctionType(.voidType, [.object, .object.nullable])) {
      throw ArgumentError('Invalid generator entry signature.');
    }
  }
}

/// SDK stream controller entries used by an async generator activation.
final class AsyncGeneratorRuntime(
  final FunctionTarget create,
  final FunctionTarget start,
  final FunctionTarget yieldValue,
  final FunctionTarget yieldStream,
  final FunctionTarget complete,
) {
  this {
    for (final target in [create, start]) {
      if (target.kind != .function || target.typeParameters.length != 1) {
        throw ArgumentError('Invalid async generator entry: ${target.name}');
      }
      final t = target.typeParameters.single;
      final signature = target == create
          ? FunctionType(.object, [AsyncRuntime.callback], typeParameters: [t])
          : FunctionType(CoreTypes.streamOf(t), [.object], typeParameters: [t]);
      if (target.signature != signature) {
        throw ArgumentError(
          'Invalid async generator entry signature: ${target.name}',
        );
      }
    }
    for (final (target, signature) in [
      (yieldValue, FunctionType(.boolean, [.object, .object.nullable])),
      (yieldStream, FunctionType(.boolean, [.object, .object])),
      (complete, FunctionType(.voidType, [.object, .object.nullable])),
    ]) {
      if (target.kind != .function || target.signature != signature) {
        throw ArgumentError(
          'Invalid async generator entry signature: ${target.name}',
        );
      }
    }
  }
}
