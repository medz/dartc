/// A selected two-input encoding with explicit physical operand constraints.
///
/// The encoding consumes no incoming flags and may change only its destination
/// and condition flags, except for registers listed in [fixed].clobbered.
/// Inputs may alias unless [fixed] specifies distinct locations; [reuseLeft]
/// requires the left input to occupy the destination.
final class BinaryEncoding<R>(
  void Function(R, R, R) encode, {
  final bool reuseLeft = false,
  final ({R left, R right, R result, Set<R> clobbered})? fixed,
}) {
  final void Function(R, R, R) _encode = encode;

  this {
    if (fixed case final locations?
        when locations.left == locations.right ||
            reuseLeft && locations.result != locations.left) {
      throw ArgumentError('Conflicting fixed operand constraints.');
    }
  }

  /// Checks the assigned operands and emits the selected instruction sequence.
  void emit(R destination, R left, R right) {
    if (reuseLeft && destination != left) {
      throw StateError(
        'Selected encoding requires the destination as its left input.',
      );
    }
    if (fixed case final locations?
        when destination != locations.result ||
            left != locations.left ||
            right != locations.right) {
      throw StateError('Selected encoding requires fixed operand registers.');
    }
    _encode(destination, left, right);
  }
}
