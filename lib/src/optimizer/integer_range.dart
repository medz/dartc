/// Inclusive bounds for the signed 64-bit Dart integer value domain.
final class FlowIntegerRange(final int lower, final int upper) {
  static const minimum = -0x8000000000000000;
  static const maximum = 0x7fffffffffffffff;
  static final full = FlowIntegerRange(minimum, maximum);

  this {
    if (lower > upper) throw ArgumentError('Empty integer range.');
  }

  int? get constant => lower == upper ? lower : null;

  bool contains(int value) => lower <= value && value <= upper;

  /// Widening drops an expanding bound at a control-flow back edge.
  FlowIntegerRange join(FlowIntegerRange other, {bool widen = false}) =>
      FlowIntegerRange(
        other.lower < lower ? (widen ? minimum : other.lower) : lower,
        other.upper > upper ? (widen ? maximum : other.upper) : upper,
      );

  FlowIntegerRange? intersect(FlowIntegerRange other) {
    final low = lower > other.lower ? lower : other.lower;
    final high = upper < other.upper ? upper : other.upper;
    return low <= high ? FlowIntegerRange(low, high) : null;
  }

  FlowIntegerRange add(FlowIntegerRange other) => _checked(
    BigInt.from(lower) + BigInt.from(other.lower),
    BigInt.from(upper) + BigInt.from(other.upper),
  );

  FlowIntegerRange subtract(FlowIntegerRange other) => _checked(
    BigInt.from(lower) - BigInt.from(other.upper),
    BigInt.from(upper) - BigInt.from(other.lower),
  );

  FlowIntegerRange multiply(FlowIntegerRange other) {
    final products = [
      for (final left in [lower, upper])
        for (final right in [other.lower, other.upper])
          BigInt.from(left) * BigInt.from(right),
    ]..sort();
    return _checked(products.first, products.last);
  }

  static FlowIntegerRange _checked(BigInt lower, BigInt upper) =>
      lower < BigInt.from(minimum) || upper > BigInt.from(maximum)
      ? full
      : FlowIntegerRange(lower.toInt(), upper.toInt());

  @override
  bool operator ==(Object other) =>
      other is FlowIntegerRange && lower == other.lower && upper == other.upper;

  @override
  int get hashCode => Object.hash(lower, upper);
}
