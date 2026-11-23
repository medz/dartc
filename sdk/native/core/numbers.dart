import 'dart:_heap/machine.dart' 
    show formatDouble, load8, outputBuffer, parseDouble, store8;
import 'dart:_heap/objects.dart'
    show floatBits, floatToInt, intToFloat, storeUint8;

@patch
class _IntegerImplementation {
  @patch
  int _bitAndFromInteger(int other) => other & this;
  @patch
  int _bitOrFromInteger(int other) => other | this;
  @patch
  int _bitXorFromInteger(int other) => other ^ this;
  @patch
  int _shrFromInteger(int other) => other >> this;
  @patch
  int _ushrFromInteger(int other) => other >>> this;
  @patch
  int _shlFromInteger(int other) => other << this;
  @patch
  int _addFromInteger(int other) => other + this;
  @patch
  int _subFromInteger(int other) => other - this;
  @patch
  int _mulFromInteger(int other) => other * this;
  @patch
  int _truncDivFromInteger(int other) => other ~/ this;
  @patch
  int _moduloFromInteger(int other) => other % this;
  @patch
  bool _greaterThanFromInteger(int other) => other > this;
  @patch
  bool _equalToInteger(int other) => this == other;
}

@patch
class _Mint {
  /// The middle of the product with a constant, as the official runtime does.
  @patch
  int get hashCode {
    const factor = 0x2d51;
    final int value = this;
    final low = (value & 0xffffffff) * factor;
    final high = (value >>> 32) * factor + (low >>> 32);
    final mixed = (high >>> 32) ^ (value * factor);
    return (mixed ^ (mixed >>> 32)) & 0x3fffffff;
  }

  @patch
  int operator ~() => -1 - this;

  @patch
  int get bitLength {
    var rest = this < 0 ? ~this : this;
    var length = 0;
    while (rest != 0) {
      rest >>= 1;
      length++;
    }
    return length;
  }

  String toString() {
    // Of numbers, the smallest has no positive counterpart.
    var rest = this < 0 ? this : -this;
    var digits = 1;
    for (var left = rest ~/ 10; left != 0; left ~/= 10) {
      digits++;
    }
    final length = this < 0 ? digits + 1 : digits;
    final result = _OneByteString._allocate(length);
    if (this < 0) storeUint8(result, 0, 45);
    for (var at = length - 1; at >= length - digits; at--) {
      final next = rest ~/ 10;
      storeUint8(result, at, 48 + next * 10 - rest);
      rest = next;
    }
    return result;
  }
}

@patch
class _Double {
  @patch
  factory _Double.fromInteger(int value) =>
      unsafeCast<_Double>(intToFloat(value));

  @patch
  int get hashCode {
    if (this >= -9223372036854775808.0 && this < 9223372036854775808.0) {
      final whole = floatToInt(this);
      if (intToFloat(whole) == this) return whole.hashCode;
    }
    final bits = floatBits(this);
    return (bits ^ (bits >>> 32)) & 0x3fffffffffffffff;
  }

  @patch
  double _add(double other) => this + other;
  @patch
  double _sub(double other) => this - other;
  @patch
  double _mul(double other) => this * other;
  @patch
  double _div(double other) => this / other;
  @patch
  double _modulo(double other) => this % other;
  @patch
  double _remainder(double other) =>
      isNegative ? -((-this) % other) : this % other;
  @patch
  double operator -() => -this;
  @patch
  bool _equal(double other) => this == other;
  @patch
  bool _equalToInteger(int other) => this == intToFloat(other);
  @patch
  bool _greaterThan(double other) => this > other;
  @patch
  bool _greaterThanFromInteger(int other) => intToFloat(other) > this;

  @patch
  bool get isNegative => this < 0 || this == 0 && floatBits(this) < 0;
  @patch
  bool get isInfinite => this == double.infinity || this == -double.infinity;
  @patch
  bool get isNaN => this != this;

  /// Whether every value as large is an integer, or none.
  bool get _isWhole => !(this > -4503599627370496.0 && this < 4503599627370496.0);

  @patch
  double truncateToDouble() {
    if (_isWhole) return this;
    final result = intToFloat(floatToInt(this));
    return result == 0 && isNegative ? -0.0 : result;
  }

  @patch
  double roundToDouble() {
    if (_isWhole) return this;
    final whole = truncateToDouble(), rest = this - whole;
    if (rest >= 0.5) return whole + 1.0;
    return rest <= -0.5 ? whole - 1.0 : whole;
  }

  @patch
  double floorToDouble() {
    final whole = truncateToDouble();
    return whole > this ? whole - 1.0 : whole;
  }

  @patch
  double ceilToDouble() {
    final whole = truncateToDouble();
    if (!(whole < this)) return whole;
    return whole + 1.0;
  }

  @patch
  int toInt() {
    if (isNaN || isInfinite) _throwNotFinite();
    return floatToInt(this);
  }

  @patch
  String toString() => _toString();

  @patch
  String _toString() {
    if (isNaN) return 'NaN';
    if (isInfinite) return this < 0 ? '-Infinity' : 'Infinity';
    final text = _Decimal._shortest(this);
    final sign = isNegative ? '-' : '';
    if (this == 0) return '${sign}0.0';
    return '$sign${text._plain()}';
  }

  String get _sign => isNegative ? '-' : '';

  @patch
  String _toStringAsFixed(int fractionDigits) {
    final text = _Decimal._exact(this);
    final rounded = text._rounded(text._point + fractionDigits);
    final digits = rounded._padded(fractionDigits);
    final sign = _sign;
    if (fractionDigits == 0) return '$sign$digits';
    final point = digits.length - fractionDigits;
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }

  @patch
  String _toStringAsExponential(int fractionDigits) {
    var text = fractionDigits < 0
        ? _Decimal._shortest(this)
        : _Decimal._exact(this)._rounded(fractionDigits + 1);
    if (this == 0) text = _Decimal('0', 1);
    return '$_sign${text._scientific(fractionDigits + 1)}';
  }

  @patch
  String _toStringAsPrecision(int fractionDigits) {
    final precision = fractionDigits;
    final text = this == 0
        ? _Decimal('0', 1)
        : _Decimal._exact(this)._rounded(precision);
    final point = text._point;
    if (point < -5 || point > precision) {
      return '$_sign${text._scientific(precision)}';
    }
    final digits = text._digits + _Decimal._zeros(precision - text._digits.length);
    if (point <= 0) return '${_sign}0.${_Decimal._zeros(-point)}$digits';
    if (point == precision) return '$_sign$digits';
    return '$_sign${digits.substring(0, point)}.${digits.substring(point)}';
  }
}

@patch
class double {
  @patch
  static double? _nativeParse(String str, int start, int end) {
    final buffer = outputBuffer();
    var at = start, digits = 0;
    bool isDigit() =>
        at < end && str.codeUnitAt(at) >= 48 && str.codeUnitAt(at) < 58;
    bool skip(int unit) {
      final isHere = at < end && (str.codeUnitAt(at) | 32) == unit;
      if (isHere) at++;
      return isHere;
    }

    if (!skip(45) && at < end && str.codeUnitAt(at) == 43) at++;
    for (; isDigit(); at++) {
      digits++;
    }
    if (skip(46)) {
      for (; isDigit(); at++) {
        digits++;
      }
    }
    if (digits == 0) return null;
    if (skip(101)) {
      if (!skip(45) && at < end && str.codeUnitAt(at) == 43) at++;
      if (!isDigit()) return null;
      for (; isDigit(); at++) {}
    }
    if (at < end || end - start > 4000) return null;
    for (var i = start; i < end; i++) {
      store8(buffer + i - start, str.codeUnitAt(i));
    }
    store8(buffer + end - start, 0);
    return parseDouble(buffer);
  }
}

/// The digits of a positive number, and how many are before its point.
final class _Decimal {
  final String _digits;
  final int _point;
  _Decimal(this._digits, this._point);

  /// The fewest digits that only [value] is read from.
  factory _Decimal._shortest(double value) {
    var count = 0;
    final positive = value < 0 ? -value : value;
    do {
      count++;
      formatDouble(positive, count, outputBuffer());
    } while (count < 17 && parseDouble(outputBuffer()) != positive);
    return _Decimal._read();
  }

  /// So many digits of [value] that the rest tells only whether it is larger.
  factory _Decimal._exact(double value) {
    if (value == 0) return _Decimal('0', 1);
    formatDouble(value < 0 ? -value : value, 80, outputBuffer());
    return _Decimal._read();
  }

  /// With the first [count] digits only.
  _Decimal _rounded(int count) {
    if (count >= _digits.length) return this;
    if (count < 0) return _Decimal('0', 1);
    final isUp = _digits.codeUnitAt(count) >= 53;
    final kept = _digits.substring(0, count);
    if (!isUp) return count == 0 ? _Decimal('0', 1) : _Decimal(kept, _point);
    // Nines become zeros, and what is before them grows.
    var end = count;
    while (end > 0 && kept.codeUnitAt(end - 1) == 57) {
      end--;
    }
    if (end == 0) return _Decimal('1', _point + 1);
    final last = String.fromCharCode(kept.codeUnitAt(end - 1) + 1);
    return _Decimal('${kept.substring(0, end - 1)}$last', _point);
  }

  /// All digits with [fraction] of them after the point, without it.
  ///
  /// There are no more of them than that.
  String _padded(int fraction) {
    final isZero = _digits == '0';
    var result = isZero ? '' : _digits;
    final point = isZero ? 0 : _point;
    if (point < 0) result = '${_zeros(-point)}$result';
    final after = result.length - (point < 0 ? 0 : point);
    result = '$result${_zeros(fraction - after)}';
    return '${_zeros(fraction + 1 - result.length)}$result';
  }

  /// With an exponent and at least [count] digits.
  String _scientific(int count) {
    final exponent = _point - 1;
    final all = '$_digits${_zeros(count - _digits.length)}';
    final rest = all.length == 1 ? '' : '.${all.substring(1)}';
    return '${all.substring(0, 1)}$rest'
        'e${exponent < 0 ? '' : '+'}$exponent';
  }

  /// Reads what there is in the buffer.
  factory _Decimal._read() {
    final buffer = outputBuffer();
    var digits = '', point = 0, isBefore = true, at = buffer;
    var byte = load8(at);
    for (; byte != 0 && byte != 101; byte = load8(++at)) {
      if (byte == 46) {
        isBefore = false;
      } else if (byte != 48 || digits.length > 0) {
        digits = digits + String.fromCharCode(byte);
        if (isBefore) point++;
      } else if (!isBefore) {
        point--;
      }
    }
    if (byte == 101) {
      final isNegative = load8(at + 1) == 45;
      var exponent = 0;
      for (at += 2; load8(at) != 0; at++) {
        exponent = exponent * 10 + load8(at) - 48;
      }
      point += isNegative ? -exponent : exponent;
    }
    var end = digits.length;
    while (end > 1 && digits.codeUnitAt(end - 1) == 48) {
      end--;
    }
    return _Decimal(digits.substring(0, end), point);
  }

  static String _zeros(int count) {
    var result = '';
    for (var i = 0; i < count; i++) {
      result = result + '0';
    }
    return result;
  }

  /// As `toString` writes it.
  String _plain() {
    final length = _digits.length;
    if (_point > 21 || _point < -5) {
      return _scientific(1);
    }
    if (_point <= 0) return '0.${_zeros(-_point)}$_digits';
    if (_point >= length) return '$_digits${_zeros(_point - length)}.0';
    return '${_digits.substring(0, _point)}.${_digits.substring(_point)}';
  }
}

@patch
class _BigIntImpl {
  @patch
  static final bool _isIntrinsified = false;
}
