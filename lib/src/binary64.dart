import 'host.dart';
import 'unicode.dart';

// Binary64 values are transported as their 64-bit IEEE bit patterns. Decimal
// conversion uses exact integer ratios; only arithmetic uses machine primitives.
const int binary64Sign = -9223372036854775808;
const int binary64Fraction = 0x000fffffffffffff;
const int binary64Infinity = 0x7ff0000000000000;
const int binary64NaN = 0x7ff8000000000000;
const int _wordBits = 30;
const int _wordBase = 1 << _wordBits;
const int _wordMask = _wordBase - 1;

bool binary64IsNaN(int value) =>
    (value & 0x7fffffffffffffff) > binary64Infinity;

List<int> _words(int value) {
  final result = <int>[];
  while (value != 0) {
    result.add(value & _wordMask);
    value >>>= _wordBits;
  }
  return result;
}

void _trim(List<int> value) {
  while (value.isNotEmpty && value.last == 0) value.removeLast();
}

int _compare(List<int> left, List<int> right) {
  if (left.length != right.length) return left.length < right.length ? -1 : 1;
  var i = left.length;
  while (i > 0) {
    i--;
    if (left[i] != right[i]) return left[i] < right[i] ? -1 : 1;
  }
  return 0;
}

int _bits(List<int> value) {
  if (value.isEmpty) return 0;
  var result = (value.length - 1) * _wordBits;
  var high = value.last;
  while (high != 0) {
    high >>= 1;
    result++;
  }
  return result;
}

void _multiply(List<int> value, int factor, [int carry = 0]) {
  for (var i = 0; i < value.length; i++) {
    final next = value[i] * factor + carry;
    value[i] = next & _wordMask;
    carry = next >> _wordBits;
  }
  if (carry != 0) value.add(carry);
}

List<int> _shift(List<int> value, int bits) {
  if (value.isEmpty) return <int>[];
  final result = List<int>.filled(bits ~/ _wordBits, 0, growable: true);
  var carry = 0;
  final partial = bits % _wordBits;
  for (final word in value) {
    final next = (word << partial) | carry;
    result.add(next & _wordMask);
    carry = next >> _wordBits;
  }
  if (carry != 0) result.add(carry);
  return result;
}

void _subtract(List<int> left, List<int> right) {
  var borrow = 0;
  for (var i = 0; i < left.length; i++) {
    var next = left[i] - borrow;
    if (i < right.length) next -= right[i];
    borrow = next < 0 ? 1 : 0;
    left[i] = next & _wordMask;
  }
  _trim(left);
}

// The caller scales the ratio to at most 53 quotient bits.
int _roundedQuotient(List<int> numerator, List<int> denominator) {
  var quotient = 0;
  for (var bit = _bits(numerator) - _bits(denominator); bit >= 0; bit--) {
    final shifted = _shift(denominator, bit);
    if (_compare(numerator, shifted) >= 0) {
      _subtract(numerator, shifted);
      quotient |= 1 << bit;
    }
  }
  final halfway = _compare(_shift(numerator, 1), denominator);
  if (halfway > 0 || halfway == 0 && (quotient & 1) != 0) quotient++;
  return quotient;
}

int _ratio(List<int> numerator, List<int> denominator) {
  var exponent = _bits(numerator) - _bits(denominator);
  final comparison = exponent >= 0
      ? _compare(numerator, _shift(denominator, exponent))
      : _compare(_shift(numerator, -exponent), denominator);
  if (comparison < 0) exponent--;
  if (exponent > 1023) return binary64Infinity;
  if (exponent < -1075) return 0;
  final shift = exponent < -1022 ? 1074 : 52 - exponent;
  if (shift >= 0) {
    numerator = _shift(numerator, shift);
  } else {
    denominator = _shift(denominator, -shift);
  }
  var significand = _roundedQuotient(numerator, denominator);
  if (exponent < -1022) return significand;
  if (significand == 0x0020000000000000) {
    significand >>= 1;
    exponent++;
  }
  if (exponent > 1023) return binary64Infinity;
  return ((exponent + 1023) << 52) | (significand & binary64Fraction);
}

int? binary64Parse(String source) {
  var start = 0;
  var end = source.length;
  while (start < end && unicodeWhitespace(source.codeUnitAt(start))) start++;
  while (end > start && unicodeWhitespace(source.codeUnitAt(end - 1))) end--;
  if (start == end) return null;
  var sign = 0;
  if (source.codeUnitAt(start) == 45 || source.codeUnitAt(start) == 43) {
    if (source.codeUnitAt(start) == 45) sign = binary64Sign;
    start++;
  }
  final special = source.substring(start, end);
  if (special == 'Infinity') return sign | binary64Infinity;
  if (special == 'NaN') return binary64NaN;
  var position = start;
  final digits = <int>[];
  var fraction = 0;
  var dot = false;
  while (position < end) {
    final unit = source.codeUnitAt(position);
    if (unit >= 48 && unit <= 57) {
      digits.add(unit - 48);
      if (dot) fraction++;
    } else if (unit == 46 && !dot) {
      dot = true;
    } else {
      break;
    }
    position++;
  }
  if (digits.isEmpty) return null;
  var exponent = 0;
  if (position < end &&
      (source.codeUnitAt(position) == 101 ||
          source.codeUnitAt(position) == 69)) {
    position++;
    var negative = false;
    if (position < end &&
        (source.codeUnitAt(position) == 43 ||
            source.codeUnitAt(position) == 45)) {
      negative = source.codeUnitAt(position) == 45;
      position++;
    }
    final first = position;
    while (position < end) {
      final unit = source.codeUnitAt(position);
      if (unit < 48 || unit > 57) return null;
      // Source length bounds the only exponents that can affect a finite value.
      if (exponent <= source.length + 400) exponent = exponent * 10 + unit - 48;
      position++;
    }
    if (position == first) return null;
    if (negative) exponent = -exponent;
  }
  if (position != end) return null;
  exponent -= fraction;
  var first = 0;
  var last = digits.length;
  while (first < last && digits[first] == 0) first++;
  if (first == last) return sign;
  while (digits[last - 1] == 0) {
    last--;
    exponent++;
  }
  final order = last - first + exponent - 1;
  if (order > 308) return sign | binary64Infinity;
  if (order < -324) return sign;
  final numerator = <int>[];
  for (var i = first; i < last; i++) _multiply(numerator, 10, digits[i]);
  final denominator = <int>[1];
  if (exponent > 0) {
    for (var i = 0; i < exponent; i++) _multiply(numerator, 10);
  } else {
    for (var i = 0; i < -exponent; i++) _multiply(denominator, 10);
  }
  return sign | _ratio(numerator, denominator);
}

// Integer literals in a double context must have an exact binary64 value.
int? binary64IntegerLiteral(String text) {
  var position = 0;
  var sign = 0;
  if (text.startsWith('-')) {
    sign = binary64Sign;
    position++;
  }
  var radix = 10;
  if (position + 2 <= text.length &&
      text.codeUnitAt(position) == 48 &&
      (text.codeUnitAt(position + 1) == 120 ||
          text.codeUnitAt(position + 1) == 88)) {
    radix = 16;
    position += 2;
  }
  if (position == text.length) return null;
  final value = <int>[];
  while (position < text.length) {
    final unit = text.codeUnitAt(position++);
    final digit = unit >= 48 && unit <= 57
        ? unit - 48
        : unit >= 65 && unit <= 70
        ? unit - 55
        : unit >= 97 && unit <= 102
        ? unit - 87
        : -1;
    if (digit < 0 || digit >= radix) return null;
    _multiply(value, radix, digit);
  }
  _trim(value);
  if (value.isEmpty) return sign;
  final bits = _ratio(value.sublist(0), <int>[1]);
  if (bits == binary64Infinity) return null;
  final exponent = (bits >> 52) - 1075;
  final significand = (bits & binary64Fraction) | 0x0010000000000000;
  final exact = exponent < 0
      ? _words(significand >> -exponent)
      : _shift(_words(significand), exponent);
  if (_compare(exact, value) != 0) return null;
  return sign | bits;
}

int? binary64Constant(String name, int nan) => switch (name) {
  'nan' => nan,
  'infinity' => binary64Infinity,
  'negativeInfinity' => binary64Sign | binary64Infinity,
  'maxFinite' => 0x7fefffffffffffff,
  'minPositive' => 1,
  _ => null,
};

void _powerOfTen(List<int> value, int exponent) {
  while (exponent >= 9) {
    _multiply(value, 1000000000);
    exponent -= 9;
  }
  var factor = 1;
  while (exponent > 0) {
    factor *= 10;
    exponent--;
  }
  _multiply(value, factor);
}

int _compareSum(List<int> left, List<int> right, List<int> value) {
  var length = left.length > right.length ? left.length : right.length;
  if (value.length > length) length = value.length;
  var carry = 0;
  var result = 0;
  for (var i = 0; i <= length; i++) {
    final sum =
        (i < left.length ? left[i] : 0) +
        (i < right.length ? right[i] : 0) +
        carry;
    final word = sum & _wordMask;
    carry = sum >> _wordBits;
    final other = i < value.length ? value[i] : 0;
    if (word != other) result = word < other ? -1 : 1;
  }
  return result;
}

String _formatDigits(String digits, int power) {
  while (digits.length > 1 && digits.codeUnitAt(digits.length - 1) == 48) {
    digits = digits.substring(0, digits.length - 1);
    power++;
  }
  final exponent = digits.length + power - 1;
  if (exponent < -6 || exponent >= 21) {
    var result = digits.substring(0, 1);
    if (digits.length > 1) result += '.' + digits.substring(1);
    return result + 'e' + (exponent >= 0 ? '+' : '') + exponent.toString();
  }
  final point = digits.length + power;
  if (point <= 0) {
    var result = '0.';
    for (var i = 0; i < -point; i++) result += '0';
    return result + digits;
  }
  if (point >= digits.length) {
    var result = digits;
    for (var i = digits.length; i < point; i++) result += '0';
    return result + '.0';
  }
  return digits.substring(0, point) + '.' + digits.substring(point);
}

String binary64Format(int bits) {
  final magnitude = bits & 0x7fffffffffffffff;
  if (magnitude > binary64Infinity) return 'NaN';
  final sign = bits < 0 ? '-' : '';
  if (magnitude == binary64Infinity) return sign + 'Infinity';
  if (magnitude == 0) return sign + '0.0';
  var significand = magnitude & binary64Fraction;
  final encodedExponent = magnitude >> 52;
  var exponent = encodedExponent - 1075;
  if (encodedExponent == 0) {
    exponent = -1074;
  } else {
    significand |= 0x0010000000000000;
  }
  // Powers of two above the smallest normal value have a closer lower neighbor.
  final asymmetric = encodedExponent > 1 && significand == 0x0010000000000000;
  final even = (significand & 1) == 0;
  var numerator = _words(significand << (asymmetric ? 2 : 1));
  var denominator = <int>[1];
  var lower = <int>[1];
  var upper = <int>[asymmetric ? 2 : 1];
  final shift = exponent - (asymmetric ? 2 : 1);
  if (shift >= 0) {
    numerator = _shift(numerator, shift);
    lower = _shift(lower, shift);
    upper = _shift(upper, shift);
  } else {
    denominator = _shift(denominator, -shift);
  }
  // A bounded estimate is corrected against the exact ratio before digit output.
  var decimalExponent = ((_bits(_words(significand)) - 1 + exponent) * 0.30103)
      .toInt();
  if (decimalExponent >= 0) {
    _powerOfTen(denominator, decimalExponent);
  } else {
    _powerOfTen(numerator, -decimalExponent);
    _powerOfTen(lower, -decimalExponent);
    _powerOfTen(upper, -decimalExponent);
  }
  if (_compare(numerator, denominator) < 0) {
    _multiply(numerator, 10);
    _multiply(lower, 10);
    _multiply(upper, 10);
    decimalExponent--;
  } else {
    final ten = denominator.sublist(0);
    _multiply(ten, 10);
    if (_compare(numerator, ten) >= 0) {
      denominator = ten;
      decimalExponent++;
    }
  }
  var digits = 0;
  var count = 0;
  while (true) {
    var digit = 0;
    while (_compare(numerator, denominator) >= 0) {
      _subtract(numerator, denominator);
      digit++;
    }
    final low = _compare(numerator, lower);
    final high = _compareSum(numerator, upper, denominator);
    final down = low < 0 || even && low == 0;
    final up = high > 0 || even && high == 0;
    count++;
    if (down || up) {
      final halfway = _compareSum(numerator, numerator, denominator);
      if (!down || up && (halfway > 0 || halfway == 0 && (digit & 1) != 0))
        digit++;
      digits = digits * 10 + digit;
      return sign +
          _formatDigits(digits.toString(), decimalExponent - count + 1);
    }
    digits = digits * 10 + digit;
    _multiply(numerator, 10);
    _multiply(lower, 10);
    _multiply(upper, 10);
  }
}

// compareTo orders exact numeric values; unlike mixed arithmetic comparisons,
// it must not round the integer to binary64 first.
int binary64CompareInt(int value, int integer) {
  if (binary64IsNaN(value)) return 2;
  final magnitude = value & 0x7fffffffffffffff;
  if (magnitude >= 0x43e0000000000000) {
    if (value >= 0) return 1;
    if (magnitude == 0x43e0000000000000 && integer == binary64Sign) return 0;
    return -1;
  }
  final truncated = hostFloat64ToInt(value);
  if (truncated < integer) return -1;
  if (truncated > integer) return 1;
  return hostFloat64Compare(value, hostFloat64FromInt(truncated));
}

int _significandBits(int significand, int exponent) {
  if (significand == 0) return 0;
  while (significand < 0x0010000000000000) {
    significand <<= 1;
    exponent--;
  }
  if (exponent < -1074) return significand >> (-1074 - exponent);
  return ((exponent + 1075) << 52) | (significand & binary64Fraction);
}

int binary64Remainder(int left, int right) {
  final a = left & 0x7fffffffffffffff;
  final b = right & 0x7fffffffffffffff;
  if (a >= binary64Infinity || b > binary64Infinity || b == 0)
    return binary64NaN;
  if (a < b) return left;
  final sign = left & binary64Sign;
  if (a == b) return sign;
  var x = a & binary64Fraction;
  var y = b & binary64Fraction;
  var ex = (a >> 52) - 1075;
  var ey = (b >> 52) - 1075;
  if (ex == -1075)
    ex = -1074;
  else
    x |= 0x0010000000000000;
  if (ey == -1075)
    ey = -1074;
  else
    y |= 0x0010000000000000;
  while (x < 0x0010000000000000) {
    x <<= 1;
    ex--;
  }
  while (y < 0x0010000000000000) {
    y <<= 1;
    ey--;
  }
  while (ex > ey) {
    if (x >= y) x -= y;
    if (x == 0) return sign;
    x <<= 1;
    ex--;
  }
  if (x >= y) x -= y;
  return sign | _significandBits(x, ex);
}

int binary64Modulo(int left, int right) {
  final result = binary64Remainder(left, right);
  if (binary64IsNaN(result)) return result;
  if ((result & 0x7fffffffffffffff) == 0) return 0;
  if (result < 0) return hostFloat64Add(result, right & 0x7fffffffffffffff);
  return result;
}
