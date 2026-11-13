import 'dart:typed_data';

/// Converts binary64 values to and from text with exact rounding.
abstract final class DoubleText() {
  /// Parses a whitespace-free range, rounding to the nearest binary64 value.
  static double? tryParse(String source, int start, int end) {
    RangeError.checkValidRange(start, end, source.length);
    if (start == end) return null;
    final negative = source.codeUnitAt(start) == 0x2d;
    var cursor = negative || source.codeUnitAt(start) == 0x2b
        ? start + 1
        : start;
    if (end - cursor == 8 && source.startsWith('Infinity', cursor)) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    if (end - cursor == 3 && source.startsWith('NaN', cursor)) {
      return double.nan;
    }

    var coefficient = BigInt.zero;
    var chunk = 0, chunkDigits = 0, digits = 0, significant = 0, point = -1;
    final ten = BigInt.from(10), billion = BigInt.from(1000000000);
    for (; cursor < end; cursor++) {
      final code = source.codeUnitAt(cursor);
      if (code == 0x2e && point < 0) {
        point = digits;
        continue;
      }
      if (code < 0x30 || code > 0x39) break;
      final digit = code - 0x30;
      digits++;
      if (significant == 0 && digit == 0) continue;
      significant++;
      chunk = chunk * 10 + digit;
      if (++chunkDigits == 9) {
        coefficient = coefficient * billion + BigInt.from(chunk);
        chunk = chunkDigits = 0;
      }
    }
    if (digits == 0) return null;
    var scale = point < 0 ? 0 : point - digits;
    if (cursor < end && source.codeUnitAt(cursor) | 0x20 == 0x65) {
      cursor++;
      var negativeExponent = false;
      if (cursor < end) {
        final code = source.codeUnitAt(cursor);
        negativeExponent = code == 0x2d;
        if (negativeExponent || code == 0x2b) cursor++;
      }
      final exponentStart = cursor;
      var exponent = 0;
      // Beyond this bound, no decimal point in the input can offset the exponent.
      final limit = end - start + 400;
      for (; cursor < end; cursor++) {
        final digit = source.codeUnitAt(cursor) - 0x30;
        if (digit < 0 || digit > 9) return null;
        if (exponent < limit) exponent = exponent * 10 + digit;
      }
      if (cursor == exponentStart) return null;
      scale += negativeExponent ? -exponent : exponent;
    }
    if (cursor != end) return null;
    if (significant == 0 || significant + scale < -323) {
      return negative ? -0.0 : 0.0;
    }
    if (significant + scale > 309) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    if (chunkDigits != 0) {
      coefficient = coefficient * ten.pow(chunkDigits) + BigInt.from(chunk);
    }
    var numerator = coefficient, denominator = BigInt.one;
    final factor = ten.pow(scale.abs());
    if (scale < 0) {
      denominator = factor;
    } else {
      numerator *= factor;
    }
    var exponent = numerator.bitLength - denominator.bitLength;
    if (exponent < 0
        ? numerator << -exponent < denominator
        : numerator < denominator << exponent) {
      exponent--;
    }
    final power = (exponent < -1022 ? -1022 : exponent) - 52;
    if (power < 0) {
      numerator <<= -power;
    } else {
      denominator <<= power;
    }
    var mantissa = _round(numerator, denominator, even: true).toInt();
    if (mantissa == 0x20000000000000) {
      mantissa >>= 1;
      exponent++;
    }
    if (exponent > 1023) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    var bits = exponent < -1022
        ? mantissa
        : ((exponent + 1023) << 52) | (mantissa & 0xfffffffffffff);
    if (negative) bits |= 0x8000000000000000;
    return (ByteData(8)..setUint64(0, bits)).getFloat64(0);
  }

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

  /// Formats a finite [value] below 1e21 in magnitude with 0–20 fraction digits.
  static String fixed(double value, int fractionDigits) {
    assert(value.isFinite && value.abs() < 1e21);
    assert(fractionDigits >= 0 && fractionDigits <= 20);
    final digits = _Decimal(value)
        .round(-fractionDigits)
        .toString()
        .padLeft(fractionDigits + 1, '0');
    final point = digits.length - fractionDigits;
    return _sign(value) +
        digits.substring(0, point) +
        (fractionDigits == 0 ? '' : '.${digits.substring(point)}');
  }

  /// Formats a finite [value] with 0–20 fraction digits, or -1 for shortest text.
  static String exponential(double value, int fractionDigits) {
    assert(value.isFinite && fractionDigits >= -1 && fractionDigits <= 20);
    if (fractionDigits == -1) return shortest(value, exponential: true);
    return _precision(value, fractionDigits + 1, true);
  }

  /// Formats a finite [value] with 1–21 significant digits.
  static String precision(double value, int precision) {
    assert(value.isFinite && precision >= 1 && precision <= 21);
    return _precision(value, precision, false);
  }

  static String _precision(double value, int count, bool scientific) {
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

  static BigInt _round(BigInt n, BigInt d, {required bool even}) {
    final whole = n ~/ d, remainder = n.remainder(d) * BigInt.two;
    return remainder > d || remainder == d && (!even || whole.isOdd)
        ? whole + BigInt.one
        : whole;
  }
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
    return DoubleText._round(n, d, even: even);
  }
}
