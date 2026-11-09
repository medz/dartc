import 'dart:typed_data';

// Compare exact binary values; the SDK's mixed operators can round integers.
int? numericOrder(num left, num right) {
  if (left.isNaN || right.isNaN) return null;
  if (left is int && right is int) return left.compareTo(right);
  if (left is double && right is double) {
    return left < right
        ? -1
        : left > right
        ? 1
        : 0;
  }
  final integer = left is int ? left : right as int;
  final floating = left is double ? left : right as double;
  int order;
  if (floating.isInfinite) {
    order = floating.isNegative ? 1 : -1;
  } else {
    final bits = (ByteData(8)..setFloat64(0, floating)).getInt64(0);
    final exponent = (bits >>> 52) & 0x7ff;
    final fraction = bits & 0xfffffffffffff;
    var significand = BigInt.from(
      exponent == 0 ? fraction : fraction | 0x10000000000000,
    );
    if (bits < 0) significand = -significand;
    final power = exponent == 0 ? -1074 : exponent - 1075;
    final exactInteger = BigInt.from(integer);
    order = power < 0
        ? (exactInteger << -power).compareTo(significand)
        : exactInteger.compareTo(significand << power);
  }
  return left is int ? order : -order;
}
