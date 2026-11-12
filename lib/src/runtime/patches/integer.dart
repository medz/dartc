@patch
class int {
  @patch
  int get bitLength {
    var value = this < 0 ? ~this : this;
    var bits = 0;
    while (value != 0) {
      value >>= 1;
      bits++;
    }
    return bits;
  }

  @patch
  static int parse(String source, {int? radix}) =>
      _IntegerText.parse(source, radix, true)!;

  @patch
  static int? tryParse(String source, {int? radix}) =>
      _IntegerText.parse(source, radix, false);

  @patch
  String toString() => toRadixString(10);

  @patch
  String toRadixString(int radix) {
    RangeError.checkValueInInterval(radix, 2, 36, 'radix');
    final negative = this < 0;
    // Negative accumulation also represents the minimum signed integer.
    var value = negative ? this : -this;
    final digits = <int>[];
    do {
      final next = value ~/ radix;
      final digit = next * radix - value;
      digits.add(digit < 10 ? 0x30 + digit : 0x61 + digit - 10);
      value = next;
    } while (value != 0);
    if (negative) digits.add(0x2d);
    return String.fromCharCodes(digits.reversed);
  }
}

abstract final class _IntegerText() {
  static int? parse(String source, int? radix, bool throwing) {
    int? invalid(int? offset) {
      if (throwing)
        throw FormatException('Invalid integer literal', source, offset);
      return null;
    }

    if (source.isEmpty) return invalid(0);
    if (radix != null) RangeError.checkValueInInterval(radix, 2, 36, 'radix');
    var start = 0, end = source.length;
    while (start < end &&
        _StringBase._isTwoByteWhitespace(source.codeUnitAt(start))) {
      start++;
    }
    while (end > start &&
        _StringBase._isTwoByteWhitespace(source.codeUnitAt(end - 1))) {
      end--;
    }
    if (start == end) return invalid(start);
    final sign = source.codeUnitAt(start);
    final negative = sign == 0x2d;
    if (negative || sign == 0x2b) start++;
    var unsigned = false;
    if (radix == null &&
        end - start >= 2 &&
        source.codeUnitAt(start) == 0x30 &&
        source.codeUnitAt(start + 1) | 0x20 == 0x78) {
      radix = 16;
      unsigned = !negative;
      start += 2;
    }
    if (start == end) return invalid(start);
    radix ??= 10;
    while (start < end && source.codeUnitAt(start) == 0x30) start++;
    if (unsigned && end - start > 16) return invalid(null);
    final limit = negative ? -0x8000000000000000 : -0x7fffffffffffffff;
    final minimum = limit ~/ radix;
    var value = 0;
    for (var i = start; i < end; i++) {
      final code = source.codeUnitAt(i);
      final digit = code >= 0x30 && code <= 0x39
          ? code - 0x30
          : (code | 0x20) - 0x61 + 10;
      if (digit < 0 || digit >= radix || code > 0x39 && digit < 10) {
        return invalid(i);
      }
      if (unsigned) {
        value = value * radix + digit;
      } else {
        if (value < minimum) return invalid(null);
        final product = value * radix;
        if (product < limit + digit) return invalid(null);
        value = product - digit;
      }
    }
    return unsigned || negative ? value : -value;
  }
}
