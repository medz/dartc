/// A selected two-input encoding with its destructive-operand constraint.
///
/// The encoding consumes no incoming flags and may change only its destination
/// and condition flags. It uses no scratch registers. Inputs may alias each
/// other; [reuseLeft] requires the left input to occupy the destination.
final class BinaryEncoding<R>(
  void Function(R, R, R) encode, {
  final bool reuseLeft = false,
}) {
  final void Function(R, R, R) _encode = encode;

  /// Checks the assigned operands and emits the selected instruction sequence.
  void emit(R destination, R left, R right) {
    if (reuseLeft && destination != left) {
      throw StateError(
        'Selected encoding requires the destination as its left input.',
      );
    }
    _encode(destination, left, right);
  }
}
