import 'dart:typed_data';

/// Formats binary64 values with exact decimal rounding.
abstract final class DoubleText() {
  static String shortest(double value, {bool exponential = false}) {
    if (!value.isFinite) return _special(value);
    final decimal = _Decimal(value);
    final bits = decimal.bits;
    final mantissa =
        (bits & 0xfffffffffffff) |
        (bits & 0x7ff0000000000000 == 0 ? 0 : 0x10000000000000);
    final even = mantissa.isEven;
    final power = decimal.power - 2;
    final low = BigInt.from(
      mantissa * 4 -
          (bits & 0xfffffffffffff == 0 &&
                  bits & 0x7ff0000000000000 > 0x10000000000000
              ? 1
              : 2),
    );
    final high = BigInt.from(mantissa * 4 + 2);
    var digits = '0', exponent = 0;
    if (value != 0) {
      exponent = decimal.exponent;
      for (var count = 1; count <= 17; count++) {
        final scale = exponent - count + 1;
        final rounded = decimal.round(scale, even: true);
        final factor = BigInt.from(10).pow(scale.abs());
        for (final candidate in [
          rounded,
          rounded - BigInt.one,
          rounded + BigInt.one,
        ]) {
          var n = candidate, d = BigInt.one;
          if (scale >= 0) {
            n *= factor;
          } else {
            d = factor;
          }
          if (power >= 0) {
            d <<= power;
          } else {
            n <<= -power;
          }
          final lower = n.compareTo(low * d), upper = n.compareTo(high * d);
          if ((lower > 0 || even && lower == 0) &&
              (upper < 0 || even && upper == 0)) {
            digits = candidate.toString();
            exponent += digits.length - count;
            while (digits.length > 1 && digits.endsWith('0')) {
              digits = digits.substring(0, digits.length - 1);
            }
            return _sign(value) +
                _render(
                  digits,
                  exponent,
                  scientific: exponential || exponent < -6 || exponent >= 21,
                  decimalPoint: !exponential,
                );
          }
        }
      }
      throw StateError('Binary64 decimal interval has no representation');
    }
    return _sign(value) + (exponential ? '0e+0' : '0.0');
  }

  static String fixed(double value, int fractionDigits) {
    RangeError.checkValueInInterval(fractionDigits, 0, 20, 'fractionDigits');
    if (!value.isFinite) return _special(value);
    if (value.abs() >= 1e21) return shortest(value, exponential: true);
    final digits = _Decimal(value)
        .round(-fractionDigits)
        .toString()
        .padLeft(fractionDigits + 1, '0');
    final point = digits.length - fractionDigits;
    return _sign(value) +
        digits.substring(0, point) +
        (fractionDigits == 0 ? '' : '.${digits.substring(point)}');
  }

  static String exponential(double value, int? fractionDigits) {
    if (fractionDigits == null) return shortest(value, exponential: true);
    RangeError.checkValueInInterval(fractionDigits, 0, 20, 'fractionDigits');
    return _precision(value, fractionDigits + 1, true);
  }

  static String precision(double value, int precision) {
    RangeError.checkValueInInterval(precision, 1, 21, 'precision');
    return _precision(value, precision, false);
  }

  static String _precision(double value, int count, bool scientific) {
    if (!value.isFinite) return _special(value);
    final decimal = _Decimal(value);
    var exponent = value == 0 ? 0 : decimal.exponent;
    var digits = decimal.round(exponent - count + 1).toString();
    if (digits.length > count) {
      exponent++;
      digits = digits.substring(0, count);
    }
    digits = digits.padLeft(count, '0');
    return _sign(value) +
        _render(
          digits,
          exponent,
          scientific: scientific || exponent < -6 || exponent >= count,
        );
  }

  static String _render(
    String digits,
    int exponent, {
    required bool scientific,
    bool decimalPoint = false,
  }) {
    if (scientific) {
      return '${digits[0]}${digits.length > 1 ? '.${digits.substring(1)}' : ''}e${exponent < 0 ? '' : '+'}$exponent';
    }
    final point = exponent + 1;
    if (point <= 0) return '0.${'0' * -point}$digits';
    if (point < digits.length) {
      return '${digits.substring(0, point)}.${digits.substring(point)}';
    }
    return digits + '0' * (point - digits.length) + (decimalPoint ? '.0' : '');
  }

  static String _sign(double value) => value.isNegative ? '-' : '';
  static String _special(double value) =>
      value.isNaN ? 'NaN' : '${_sign(value)}Infinity';
}

final class _Decimal(double value) {
  final int bits =
      (ByteData(8)..setFloat64(0, value)).getUint64(0) & 0x7fffffffffffffff;
  late final power = (bits >>> 52) == 0 ? -1074 : (bits >>> 52) - 1075;
  late final mantissa = BigInt.from(
    (bits & 0xfffffffffffff) | (bits >>> 52 == 0 ? 0 : 0x10000000000000),
  );
  late final numerator = power < 0 ? mantissa : mantissa << power;
  late final denominator = power < 0 ? BigInt.one << -power : BigInt.one;

  int get exponent {
    var result = numerator.toString().length - denominator.toString().length;
    final factor = BigInt.from(10).pow(result.abs());
    if (result >= 0
        ? numerator < denominator * factor
        : numerator * factor < denominator) {
      result--;
    }
    return result;
  }

  BigInt round(int scale, {bool even = false}) {
    var n = numerator, d = denominator;
    final factor = BigInt.from(10).pow(scale.abs());
    if (scale < 0) {
      n *= factor;
    } else {
      d *= factor;
    }
    final whole = n ~/ d, remainder = n.remainder(d) * BigInt.two;
    return remainder > d || remainder == d && (!even || whole.isOdd)
        ? whole + BigInt.one
        : whole;
  }
}
