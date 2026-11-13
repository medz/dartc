import 'dart:math';
import 'dart:typed_data';

Iterable<(double, double)> floatingReductionCases() sync* {
  const edges = [
    0.0,
    -0.0,
    1.0,
    -1.0,
    2.5,
    -2.5,
    double.minPositive,
    -double.minPositive,
    2.2250738585072014e-308,
    double.maxFinite,
    -double.maxFinite,
    double.infinity,
    double.negativeInfinity,
    double.nan,
  ];
  for (final a in edges) {
    for (final b in edges) {
      yield (a, b);
    }
  }
  final bits = ByteData(8), random = Random(314);
  double sample() =>
      (bits
            ..setUint32(0, random.nextInt(1 << 32))
            ..setUint32(4, random.nextInt(1 << 32)))
          .getFloat64(0);
  for (var i = 0; i < 300; i++) {
    yield (sample(), sample());
  }
}

// Compute in exact multiples of 2^-1074, independently of floating reduction.
({double remainder, double modulo}) exactFloatingReduction(double a, double b) {
  if (!a.isFinite || b.isNaN || b == 0) {
    return (remainder: double.nan, modulo: double.nan);
  }
  if (b.isInfinite) {
    return (
      remainder: a,
      modulo: a == 0
          ? 0.0
          : a < 0
          ? double.infinity
          : a,
    );
  }
  BigInt units(double value) {
    final bits = (ByteData(8)..setFloat64(0, value)).getUint64(0);
    final exponent = (bits >>> 52) & 0x7ff;
    final fraction = bits & 0xfffffffffffff;
    return exponent == 0
        ? BigInt.from(fraction)
        : BigInt.from(fraction | 0x10000000000000) << (exponent - 1);
  }

  double rounded(BigInt value) {
    final shift = max(0, value.bitLength - 53);
    var significand = value >> shift;
    if (shift > 0) {
      final tail = value - (significand << shift);
      final half = BigInt.one << (shift - 1);
      if (tail > half || tail == half && significand.isOdd) {
        significand += BigInt.one;
      }
    }
    return significand.toDouble() * pow(2.0, shift - 1074);
  }

  final dividend = units(a), divisor = units(b);
  final remainder = rounded(dividend.remainder(divisor));
  return (
    remainder: a.isNegative ? -remainder : remainder,
    modulo: rounded((a.isNegative ? -dividend : dividend) % divisor),
  );
}
