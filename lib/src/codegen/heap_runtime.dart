import 'package:dartc/ir.dart';

/// Machine services available to checked runtime source.
enum MemoryPrimitive() {
  map,
  unmap,
  fail,
}

/// Source program and entry contracts used by managed code generation.
final class HeapRuntime(
  final IrProgram program, {
  required final FunctionTarget allocate,
  required final FunctionTarget release,
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
    for (final (target, signature) in [
      (allocate, FunctionType(.integer, List.filled(5, ValueType.integer))),
      (release, FunctionType(.voidType, [.integer])),
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
      };
      if (target.kind != .function ||
          target.typeParameters.isNotEmpty ||
          target.signature != signature ||
          program.implementationOf(target) is! IrExternal) {
        throw ArgumentError('Invalid memory service: ${target.name}');
      }
    }
  }
}
