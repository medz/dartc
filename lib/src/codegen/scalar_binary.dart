import 'package:dartc/ir.dart';

import 'binary_encoding.dart';
import 'function_emitter.dart';

/// Resolves selected binary facts against the current emission sink.
BinaryEncoding<R> scalarBinaryEncoding<R>(
  FunctionEmitter<R> emitter,
  Value instruction, {
  required bool floating,
  Comparison? comparison,
  bool? constant,
}) {
  if (constant != null) {
    return BinaryEncoding(
      (destination, _, _) =>
          emitter.loadImmediate(destination, constant ? 1 : 0),
    );
  }
  if (comparison != null) {
    return emitter.comparison(comparison, floating: floating);
  }
  return switch (instruction) {
    NumericBinary(:final operator) => switch (operator) {
      .add => floating ? emitter.addDouble : emitter.add,
      .subtract => floating ? emitter.subtractDouble : emitter.subtract,
      .multiply => floating ? emitter.multiplyDouble : emitter.multiply,
      .divide => emitter.divideDouble,
      _ => throw UnsupportedError('Native numeric operation: $operator'),
    },
    IntBinary(:final operator) => switch (operator) {
      .add => emitter.add,
      .subtract => emitter.subtract,
      .multiply => emitter.multiply,
      .truncateDivide => emitter.divideSigned,
      .shiftLeft => emitter.shiftLeft,
      .shiftRight => emitter.shiftRight,
      .unsignedShiftRight => emitter.unsignedShiftRight,
      .divide => emitter.divideDouble,
      .bitAnd => emitter.bitAnd,
      .bitOr => emitter.bitOr,
      .bitXor => emitter.bitXor,
      .lessThan => emitter.comparison(.lessThan),
      .lessOrEqual => emitter.comparison(.lessOrEqual),
      .greaterThan => emitter.comparison(.greaterThan),
      .greaterOrEqual => emitter.comparison(.greaterOrEqual),
      _ => throw UnsupportedError('Native integer operation: $operator'),
    },
    _ => throw StateError('Unselected binary operation.'),
  };
}
