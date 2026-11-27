import 'dart:math' as math;

// Values of several numbers, in plain Dart.

final _single = Float32List(1);
final _doubleBits = Float64List(2).buffer.asByteData();

double _toSingle(double value) {
  storeFloat32(_single, 0, value);
  return loadFloat32(_single, 0);
}

int _bitsOfSingle(double value) {
  storeFloat32(_single, 0, value);
  return loadInt32(_single, 0);
}

double _singleOfBits(int bits) {
  storeInt32(_single, 0, bits);
  return loadFloat32(_single, 0);
}

const _singleSignBit = -0x80000000;

int _signOfSingle(int bits) => bits >> 31 & 1;

int _signOf(double value) {
  _doubleBits.setFloat64(0, value);
  return _doubleBits.getUint8(0) >> 7;
}

void _checkMask(int mask) {
  if (mask < 0 || mask > 255) throw RangeError.range(mask, 0, 255, 'mask');
}

@patch
class Float32x4 {
  @patch
  static _Float32x4 _Float32x4FromDoubles(
    double x,
    double y,
    double z,
    double w,
  ) => _Float32x4._(
    _bitsOfSingle(x),
    _bitsOfSingle(y),
    _bitsOfSingle(z),
    _bitsOfSingle(w),
  );

  @patch
  static _Float32x4 _Float32x4Splat(double v) {
    final bits = _bitsOfSingle(v);
    return _Float32x4._(bits, bits, bits, bits);
  }

  @patch
  factory Float32x4.zero() => _Float32x4._(0, 0, 0, 0);

  @patch
  factory Float32x4.fromInt32x4Bits(Int32x4 x) =>
      _Float32x4._(x.x, x.y, x.z, x.w);

  @patch
  factory Float32x4.fromFloat64x2(Float64x2 xy) =>
      _Float32x4._(_bitsOfSingle(xy.x), _bitsOfSingle(xy.y), 0, 0);
}

@patch
final class _Float32x4 {
  // The signed 32-bit words that store the exact bits of each lane.
  final int _xBits, _yBits, _zBits, _wBits;
  _Float32x4._(this._xBits, this._yBits, this._zBits, this._wBits);

  /// Each lane of this and [other] through [f], rounded.
  Float32x4 _each(Float32x4 other, double Function(double, double) f) =>
      Float32x4(f(x, other.x), f(y, other.y), f(z, other.z), f(w, other.w));

  Float32x4 _map(double Function(double) f) =>
      Float32x4(f(x), f(y), f(z), f(w));

  Int32x4 _test(Float32x4 other, bool Function(double, double) f) =>
      Int32x4.bool(f(x, other.x), f(y, other.y), f(z, other.z), f(w, other.w));

  @patch
  Float32x4 operator +(Float32x4 other) => _each(other, (a, b) => a + b);
  @patch
  Float32x4 operator -() => _Float32x4._(
    _xBits ^ _singleSignBit,
    _yBits ^ _singleSignBit,
    _zBits ^ _singleSignBit,
    _wBits ^ _singleSignBit,
  );
  @patch
  Float32x4 operator -(Float32x4 other) => _each(other, (a, b) => a - b);
  @patch
  Float32x4 operator *(Float32x4 other) => _each(other, (a, b) => a * b);
  @patch
  Float32x4 operator /(Float32x4 other) => _each(other, (a, b) => a / b);
  @patch
  Int32x4 lessThan(Float32x4 other) => _test(other, (a, b) => a < b);
  @patch
  Int32x4 lessThanOrEqual(Float32x4 other) => _test(other, (a, b) => a <= b);
  @patch
  Int32x4 greaterThan(Float32x4 other) => _test(other, (a, b) => a > b);
  @patch
  Int32x4 greaterThanOrEqual(Float32x4 other) => _test(other, (a, b) => a >= b);
  @patch
  Int32x4 equal(Float32x4 other) => _test(other, (a, b) => a == b);
  @patch
  Int32x4 notEqual(Float32x4 other) => _test(other, (a, b) => a != b);
  @patch
  Float32x4 scale(double scale) {
    final factor = _toSingle(scale);
    return _map((a) => a * factor);
  }

  @patch
  Float32x4 abs() => _Float32x4._(
    _xBits & ~_singleSignBit,
    _yBits & ~_singleSignBit,
    _zBits & ~_singleSignBit,
    _wBits & ~_singleSignBit,
  );
  @patch
  Float32x4 clamp(Float32x4 lowerLimit, Float32x4 upperLimit) =>
      max(lowerLimit).min(upperLimit);
  @patch
  double get x => _singleOfBits(_xBits);
  @patch
  double get y => _singleOfBits(_yBits);
  @patch
  double get z => _singleOfBits(_zBits);
  @patch
  double get w => _singleOfBits(_wBits);
  @patch
  int get signMask =>
      _signOfSingle(_xBits) |
      _signOfSingle(_yBits) << 1 |
      _signOfSingle(_zBits) << 2 |
      _signOfSingle(_wBits) << 3;

  int _laneBits(int index) => switch (index) {
    0 => _xBits,
    1 => _yBits,
    2 => _zBits,
    _ => _wBits,
  };

  @patch
  Float32x4 shuffle(int mask) {
    _checkMask(mask);
    return _Float32x4._(
      _laneBits(mask & 3),
      _laneBits(mask >> 2 & 3),
      _laneBits(mask >> 4 & 3),
      _laneBits(mask >> 6 & 3),
    );
  }

  @patch
  Float32x4 shuffleMix(Float32x4 zw, int mask) {
    _checkMask(mask);
    final other = zw as _Float32x4;
    return _Float32x4._(
      _laneBits(mask & 3),
      _laneBits(mask >> 2 & 3),
      other._laneBits(mask >> 4 & 3),
      other._laneBits(mask >> 6 & 3),
    );
  }

  @patch
  Float32x4 _withX(double x) =>
      _Float32x4._(_bitsOfSingle(x), _yBits, _zBits, _wBits);
  @patch
  Float32x4 _withY(double y) =>
      _Float32x4._(_xBits, _bitsOfSingle(y), _zBits, _wBits);
  @patch
  Float32x4 _withZ(double z) =>
      _Float32x4._(_xBits, _yBits, _bitsOfSingle(z), _wBits);
  @patch
  Float32x4 _withW(double w) =>
      _Float32x4._(_xBits, _yBits, _zBits, _bitsOfSingle(w));
  @patch
  Float32x4 min(Float32x4 other) => _each(other, (a, b) => a < b ? a : b);
  @patch
  Float32x4 max(Float32x4 other) => _each(other, (a, b) => a > b ? a : b);
  @patch
  Float32x4 sqrt() => _map(math.sqrt);
  @patch
  Float32x4 reciprocal() => _map((a) => 1 / a);
  @patch
  Float32x4 reciprocalSqrt() => _map((a) => 1 / math.sqrt(a));
}

@patch
class Int32x4 {
  @patch
  factory Int32x4(int x, int y, int z, int w) => _Int32x4._(
    x.toSigned(32),
    y.toSigned(32),
    z.toSigned(32),
    w.toSigned(32),
  );

  @patch
  factory Int32x4.fromFloat32x4Bits(Float32x4 x) {
    final value = x as _Float32x4;
    return _Int32x4._(value._xBits, value._yBits, value._zBits, value._wBits);
  }
}

@patch
final class _Int32x4 {
  final int _x, _y, _z, _w;
  _Int32x4._(this._x, this._y, this._z, this._w);

  @patch
  int get x => _x;
  @patch
  int get y => _y;
  @patch
  int get z => _z;
  @patch
  int get w => _w;

  @patch
  Float32x4 select(Float32x4 trueValue, Float32x4 falseValue) {
    final whenTrue = trueValue as _Float32x4;
    final whenFalse = falseValue as _Float32x4;
    int one(int mask, int ifTrue, int ifFalse) =>
        ifTrue & mask | ifFalse & ~mask;
    return _Float32x4._(
      one(_x, whenTrue._xBits, whenFalse._xBits),
      one(_y, whenTrue._yBits, whenFalse._yBits),
      one(_z, whenTrue._zBits, whenFalse._zBits),
      one(_w, whenTrue._wBits, whenFalse._wBits),
    );
  }
}

@patch
class Float64x2 {
  @patch
  static _Float64x2 _Float64x2FromDoubles(double x, double y) =>
      _Float64x2._(x, y);

  @patch
  static _Float64x2 _Float64x2Splat(double v) => _Float64x2._(v, v);

  @patch
  factory Float64x2.zero() => _Float64x2._(0.0, 0.0);

  @patch
  factory Float64x2.fromFloat32x4(Float32x4 v) => _Float64x2._(v.x, v.y);
}

@patch
final class _Float64x2 {
  final double _x, _y;
  _Float64x2._(this._x, this._y);

  Float64x2 _each(Float64x2 other, double Function(double, double) f) =>
      _Float64x2._(f(_x, other.x), f(_y, other.y));

  Float64x2 _map(double Function(double) f) => _Float64x2._(f(_x), f(_y));

  @patch
  Float64x2 operator +(Float64x2 other) => _each(other, (a, b) => a + b);
  @patch
  Float64x2 operator -() => _map((a) => -a);
  @patch
  Float64x2 operator -(Float64x2 other) => _each(other, (a, b) => a - b);
  @patch
  Float64x2 operator *(Float64x2 other) => _each(other, (a, b) => a * b);
  @patch
  Float64x2 operator /(Float64x2 other) => _each(other, (a, b) => a / b);
  @patch
  Float64x2 scale(double s) => _map((a) => a * s);
  @patch
  Float64x2 abs() => _map((a) => a.abs());
  @patch
  Float64x2 clamp(Float64x2 lowerLimit, Float64x2 upperLimit) =>
      max(lowerLimit).min(upperLimit);
  @patch
  double get x => _x;
  @patch
  double get y => _y;
  @patch
  int get signMask => _signOf(_x) | _signOf(_y) << 1;
  @patch
  Float64x2 _withX(double x) => _Float64x2._(x, _y);
  @patch
  Float64x2 _withY(double y) => _Float64x2._(_x, y);
  @patch
  Float64x2 min(Float64x2 other) => _each(other, (a, b) => a < b ? a : b);
  @patch
  Float64x2 max(Float64x2 other) => _each(other, (a, b) => a > b ? a : b);
  @patch
  Float64x2 sqrt() => _map(math.sqrt);
}

@patch
class Float32x4List {
  @patch
  factory Float32x4List(int length) {
    _checkLength(length, 16);
    return newArray<_Float32x4List>(length << 4);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Float32x4List {
  int get length => lengthOf(this) >> 4;

  @patch
  Float32x4 operator [](int index) {
    _checkRead(index, length);
    return _getFloat32x4(index << 4);
  }
}

@patch
class Int32x4List {
  @patch
  factory Int32x4List(int length) {
    _checkLength(length, 16);
    return newArray<_Int32x4List>(length << 4);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Int32x4List {
  int get length => lengthOf(this) >> 4;

  @patch
  Int32x4 operator [](int index) {
    _checkRead(index, length);
    return _getInt32x4(index << 4);
  }
}

@patch
class Float64x2List {
  @patch
  factory Float64x2List(int length) {
    _checkLength(length, 16);
    return newArray<_Float64x2List>(length << 4);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Float64x2List {
  int get length => lengthOf(this) >> 4;

  @patch
  Float64x2 operator [](int index) {
    _checkRead(index, length);
    return _getFloat64x2(index << 4);
  }
}

@patch
class _Float32x4ArrayView {
  @patch
  _Float32x4ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  Float32x4 operator [](int index) {
    _checkRead(index, length);
    return _typedData._getFloat32x4(offsetInBytes + (index << 4));
  }
}

@patch
class _Int32x4ArrayView {
  @patch
  _Int32x4ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  Int32x4 operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt32x4(offsetInBytes + (index << 4));
  }
}

@patch
class _Float64x2ArrayView {
  @patch
  _Float64x2ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  Float64x2 operator [](int index) {
    _checkRead(index, length);
    return _typedData._getFloat64x2(offsetInBytes + (index << 4));
  }
}

@patch
class _UnmodifiableFloat32x4ArrayView {
  @patch
  _UnmodifiableFloat32x4ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class _UnmodifiableInt32x4ArrayView {
  @patch
  _UnmodifiableInt32x4ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class _UnmodifiableFloat64x2ArrayView {
  @patch
  _UnmodifiableFloat64x2ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class _TypedList {
  @patch
  Float32x4 _getFloat32x4(int offsetInBytes) => _Float32x4._(
    _getInt32(offsetInBytes),
    _getInt32(offsetInBytes + 4),
    _getInt32(offsetInBytes + 8),
    _getInt32(offsetInBytes + 12),
  );
  @patch
  void _setFloat32x4(int offsetInBytes, Float32x4 value) {
    final lanes = value as _Float32x4;
    _setInt32(offsetInBytes, lanes._xBits);
    _setInt32(offsetInBytes + 4, lanes._yBits);
    _setInt32(offsetInBytes + 8, lanes._zBits);
    _setInt32(offsetInBytes + 12, lanes._wBits);
  }

  @patch
  Int32x4 _getInt32x4(int offsetInBytes) => Int32x4(
    _getInt32(offsetInBytes),
    _getInt32(offsetInBytes + 4),
    _getInt32(offsetInBytes + 8),
    _getInt32(offsetInBytes + 12),
  );
  @patch
  void _setInt32x4(int offsetInBytes, Int32x4 value) {
    _setInt32(offsetInBytes, value.x);
    _setInt32(offsetInBytes + 4, value.y);
    _setInt32(offsetInBytes + 8, value.z);
    _setInt32(offsetInBytes + 12, value.w);
  }

  @patch
  Float64x2 _getFloat64x2(int offsetInBytes) =>
      Float64x2(_getFloat64(offsetInBytes), _getFloat64(offsetInBytes + 8));
  @patch
  void _setFloat64x2(int offsetInBytes, Float64x2 value) {
    _setFloat64(offsetInBytes, value.x);
    _setFloat64(offsetInBytes + 8, value.y);
  }
}
