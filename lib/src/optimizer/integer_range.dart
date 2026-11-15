/// Signed 64-bit bounds, a power-of-two stride and an optional exclusion of zero.
final class FlowIntegerRange._(
  final int lower,
  final int upper,
  final int strideBits,
  final int residue,
  final bool excludesZero,
) {
  static const minimum = -0x8000000000000000;
  static const maximum = 0x7fffffffffffffff;
  static final full = FlowIntegerRange(minimum, maximum);

  factory(
    int lower,
    int upper, {
    int strideBits = 0,
    int residue = 0,
    bool excludesZero = false,
  }) {
    RangeError.checkValueInInterval(strideBits, 0, 64, 'strideBits');
    residue &= _mask(strideBits);
    final bounds = _bounds(lower, upper, strideBits, residue, excludesZero);
    if (bounds == null) throw ArgumentError('Empty integer range.');
    final (low, high) = bounds;
    return FlowIntegerRange._(
      low,
      high,
      low == high ? 64 : strideBits,
      low == high ? low : residue,
      excludesZero && residue == 0 && low < 0 && high > 0,
    );
  }

  int? get constant => lower == upper ? lower : null;

  /// The number of low bits guaranteed zero in every represented value.
  int get zeroBits {
    final bits = _zeroBits(residue);
    return bits < strideBits ? bits : strideBits;
  }

  bool contains(int value) =>
      lower <= value &&
      value <= upper &&
      value & _mask(strideBits) == residue &&
      (value != 0 || !excludesZero);

  /// Widening drops an expanding bound at a control-flow back edge.
  FlowIntegerRange join(FlowIntegerRange other, {bool widen = false}) {
    var bits = strideBits < other.strideBits ? strideBits : other.strideBits;
    final agreement = _zeroBits(residue ^ other.residue);
    if (agreement < bits) bits = agreement;
    return FlowIntegerRange(
      other.lower < lower ? (widen ? minimum : other.lower) : lower,
      other.upper > upper ? (widen ? maximum : other.upper) : upper,
      strideBits: bits,
      residue: residue,
      excludesZero: !contains(0) && !other.contains(0),
    );
  }

  FlowIntegerRange? intersect(FlowIntegerRange other) {
    final common = strideBits < other.strideBits
        ? strideBits
        : other.strideBits;
    if ((residue ^ other.residue) & _mask(common) != 0) return null;
    final low = lower > other.lower ? lower : other.lower;
    final high = upper < other.upper ? upper : other.upper;
    final selected = strideBits > other.strideBits ? this : other;
    final nonzero = !contains(0) || !other.contains(0);
    return _bounds(low, high, selected.strideBits, selected.residue, nonzero) ==
            null
        ? null
        : FlowIntegerRange(
            low,
            high,
            strideBits: selected.strideBits,
            residue: selected.residue,
            excludesZero: nonzero,
          );
  }

  FlowIntegerRange add(FlowIntegerRange other) => _checked(
    BigInt.from(lower) + BigInt.from(other.lower),
    BigInt.from(upper) + BigInt.from(other.upper),
    strideBits < other.strideBits ? strideBits : other.strideBits,
    residue + other.residue,
  );

  FlowIntegerRange subtract(FlowIntegerRange other) => _checked(
    BigInt.from(lower) - BigInt.from(other.upper),
    BigInt.from(upper) - BigInt.from(other.lower),
    strideBits < other.strideBits ? strideBits : other.strideBits,
    residue - other.residue,
  );

  FlowIntegerRange multiply(FlowIntegerRange other) {
    final products = [
      for (final left in [lower, upper])
        for (final right in [other.lower, other.upper])
          BigInt.from(left) * BigInt.from(right),
    ]..sort();
    final leftBits = strideBits + other.zeroBits;
    final rightBits = other.strideBits + zeroBits;
    final bits = leftBits < rightBits ? leftBits : rightBits;
    return _checked(
      products.first,
      products.last,
      bits > 64 ? 64 : bits,
      residue * other.residue,
    );
  }

  static FlowIntegerRange _checked(
    BigInt lower,
    BigInt upper,
    int bits,
    int residue,
  ) => lower < BigInt.from(minimum) || upper > BigInt.from(maximum)
      ? FlowIntegerRange(minimum, maximum, strideBits: bits, residue: residue)
      : FlowIntegerRange(
          lower.toInt(),
          upper.toInt(),
          strideBits: bits,
          residue: residue,
        );

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

  static (int, int)? _bounds(
    int lower,
    int upper,
    int bits,
    int residue,
    bool nonzero,
  ) {
    if (lower > upper) return null;
    if (bits == 64) {
      return lower <= residue && residue <= upper && (!nonzero || residue != 0)
          ? (residue, residue)
          : null;
    }
    final mask = _mask(bits);
    var low = lower + ((residue - (lower & mask)) & mask);
    var high = upper - (((upper & mask) - residue) & mask);
    if (nonzero) {
      if (low == 0) {
        if (bits == 63) return null;
        low = 1 << bits;
      }
      if (high == 0) high = bits == 63 ? minimum : -(1 << bits);
    }
    return low >= lower && high <= upper && low <= high ? (low, high) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FlowIntegerRange &&
      lower == other.lower &&
      upper == other.upper &&
      strideBits == other.strideBits &&
      residue == other.residue &&
      excludesZero == other.excludesZero;

  @override
  int get hashCode =>
      Object.hash(lower, upper, strideBits, residue, excludesZero);
}
