import 'package:dartc/ir.dart';

/// Checked source functions used while allocating and moving managed objects.
///
/// Their transitive call dependencies must be supplied in the program and must
/// not allocate, throw or enter foreign code. Code generation checks that closure.
/// Pointer arguments must be consumed as addresses without observing, returning
/// or retaining their Dart object identities; entry must not require boxing.
final class HeapRuntime({
  /// Calculates capacity from current and required bytes, or returns zero.
  ///
  /// A successful capacity must satisfy the requirement and not exceed `2^61`.
  required final IrFunction capacity,

  /// Copies a word count between aligned, valid, nonoverlapping native regions.
  required final IrFunction copy,

  /// Clears a word count in an aligned, writable native region.
  required final IrFunction clear,
}) {
  /// The ordinary Dart bodies required by the heap implementation.
  Iterable<IrFunction> get functions => [capacity, copy, clear];

  this {
    final pointer = FfiTypes.int64Pointer;
    for (final (function, signature) in [
      (capacity, FunctionType(.integer, [.integer, .integer])),
      (copy, FunctionType(.voidType, [pointer, pointer, .integer])),
      (clear, FunctionType(.voidType, [pointer, .integer])),
    ]) {
      final target = function.target;
      if (target.kind != .function ||
          target.typeParameters.isNotEmpty ||
          target.signature != signature) {
        throw ArgumentError('Invalid heap runtime signature: ${target.name}');
      }
    }
  }
}
