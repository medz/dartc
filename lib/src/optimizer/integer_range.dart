/// Inclusive signed 64-bit bounds, alignment and an optional exclusion of zero.
final class FlowIntegerRange._(
  final int lower,
  final int upper,
  final int zeroBits,
  final bool excludesZero,
) {
  static const minimum = -0x8000000000000000;
  static const maximum = 0x7fffffffffffffff;
  static final full = FlowIntegerRange(minimum, maximum);

  factory(int lower, int upper, {int zeroBits = 0, bool excludesZero = false}) {
    RangeError.checkValueInInterval(zeroBits, 0, 64, 'zeroBits');
    final bounds = _bounds(lower, upper, zeroBits, excludesZero);
    if (bounds == null) throw ArgumentError('Empty integer range.');
    final (low, high) = bounds;
    return FlowIntegerRange._(
      low,
      high,
      low == high ? _zeroBits(low) : zeroBits,
      excludesZero && low < 0 && high > 0,
    );
  }

  int? get constant => lower == upper ? lower : null;

  bool contains(int value) =>
      lower <= value &&
      value <= upper &&
      value & _mask(zeroBits) == 0 &&
      (value != 0 || !excludesZero);

  /// Widening drops an expanding bound at a control-flow back edge.
  FlowIntegerRange join(FlowIntegerRange other, {bool widen = false}) =>
      FlowIntegerRange(
        other.lower < lower ? (widen ? minimum : other.lower) : lower,
        other.upper > upper ? (widen ? maximum : other.upper) : upper,
        zeroBits: zeroBits < other.zeroBits ? zeroBits : other.zeroBits,
        excludesZero: !contains(0) && !other.contains(0),
      );

  FlowIntegerRange? intersect(FlowIntegerRange other) {
    final low = lower > other.lower ? lower : other.lower;
    final high = upper < other.upper ? upper : other.upper;
    final bits = zeroBits > other.zeroBits ? zeroBits : other.zeroBits;
    final nonzero = !contains(0) || !other.contains(0);
    return _bounds(low, high, bits, nonzero) == null
        ? null
        : FlowIntegerRange(low, high, zeroBits: bits, excludesZero: nonzero);
  }

  FlowIntegerRange add(FlowIntegerRange other) => _checked(
    BigInt.from(lower) + BigInt.from(other.lower),
    BigInt.from(upper) + BigInt.from(other.upper),
    zeroBits < other.zeroBits ? zeroBits : other.zeroBits,
  );

  FlowIntegerRange subtract(FlowIntegerRange other) => _checked(
    BigInt.from(lower) - BigInt.from(other.upper),
    BigInt.from(upper) - BigInt.from(other.lower),
    zeroBits < other.zeroBits ? zeroBits : other.zeroBits,
  );

  FlowIntegerRange multiply(FlowIntegerRange other) {
    final products = [
      for (final left in [lower, upper])
        for (final right in [other.lower, other.upper])
          BigInt.from(left) * BigInt.from(right),
    ]..sort();
    final bits = zeroBits + other.zeroBits;
    return _checked(products.first, products.last, bits > 64 ? 64 : bits);
  }

  static FlowIntegerRange _checked(BigInt lower, BigInt upper, int zeroBits) =>
      lower < BigInt.from(minimum) || upper > BigInt.from(maximum)
      ? FlowIntegerRange(minimum, maximum, zeroBits: zeroBits)
      : FlowIntegerRange(lower.toInt(), upper.toInt(), zeroBits: zeroBits);

  static int _mask(int bits) => -1 >>> (64 - bits);

  static int _zeroBits(int value) {
    if (value == 0) return 64;
    var count = 0;
    while (value & 1 == 0) {
      count++;
      value >>>= 1;
    }
    return count;
  }

  static (int, int)? _bounds(int lower, int upper, int bits, bool nonzero) {
    if (lower > upper) return null;
    if (bits == 64) return !nonzero && lower <= 0 && upper >= 0 ? (0, 0) : null;
    final mask = _mask(bits);
    var low = lower + (-(lower & mask) & mask);
    var high = upper - (upper & mask);
    if (nonzero) {
      if (low == 0) {
        if (bits == 63) return null;
        low = 1 << bits;
      }
      if (high == 0) high = bits == 63 ? minimum : -(1 << bits);
    }
    // Rounding upwards can wrap beyond the signed integer domain.
    return low >= lower && low <= high ? (low, high) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FlowIntegerRange &&
      lower == other.lower &&
      upper == other.upper &&
      zeroBits == other.zeroBits &&
      excludesZero == other.excludesZero;

  @override
  int get hashCode => Object.hash(lower, upper, zeroBits, excludesZero);
}
