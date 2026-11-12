import 'contracts.dart';

/// Reduces by powers of two, keeping each subtraction exact.
@RuntimeEntry(.floatingRemainder)
double floatingRemainder(double value, double divisor) {
  if (value.isInfinite || value.isNaN || divisor.isNaN || divisor == 0) {
    return double.nan;
  }
  var remainder = value.abs();
  final magnitude = divisor.abs();
  if (remainder < magnitude) return value;
  var scaled = magnitude;
  while (scaled <= remainder * 0.5) {
    scaled *= 2;
  }
  while (remainder >= magnitude) {
    if (remainder >= scaled) remainder -= scaled;
    scaled *= 0.5;
  }
  return value.isNegative ? -remainder : remainder;
}

/// Euclidean floating modulo, including positive zero for exact multiples.
@RuntimeEntry(.floatingModulo)
double floatingModulo(double value, double divisor) {
  final remainder = floatingRemainder(value, divisor);
  return remainder == 0
      ? 0
      : remainder < 0
      ? remainder + divisor.abs()
      : remainder;
}
