import 'dart:math' as math;

// Values of several numbers, in plain Dart. Lanes of Float32x4 are rounded to
// single precision as the machine does.

final _single = Float32List(4);
final _singleBits = _single.buffer.asInt32List();
final _doubleBits = Float64List(2).buffer.asByteData();

double _toSingle(double value) {
  _single[0] = value;
  return _single[0];
}

int _bitsOfSingle(double value) {
  _single[0] = value;
  return _singleBits[0];
}

double _singleOfBits(int bits) {
  _singleBits[0] = bits;
  return _single[0];
}

int _signOf(double value) {
  _doubleBits.setFloat64(0, value);
  return _doubleBits.getUint8(0) >> 7;
}

/// The lane [index] of four.
T _lane<T>(int index, T x, T y, T z, T w) => switch (index) {
  0 => x,
  1 => y,
  2 => z,
  _ => w,
};

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
  ) => _Float32x4._(_toSingle(x), _toSingle(y), _toSingle(z), _toSingle(w));

  @patch
  static _Float32x4 _Float32x4Splat(double v) {
    final value = _toSingle(v);
    return _Float32x4._(value, value, value, value);
  }

  @patch
  factory Float32x4.zero() => _Float32x4._(0.0, 0.0, 0.0, 0.0);

  @patch
  factory Float32x4.fromInt32x4Bits(Int32x4 x) => _Float32x4._(
    _singleOfBits(x.x),
    _singleOfBits(x.y),
    _singleOfBits(x.z),
    _singleOfBits(x.w),
  );

  @patch
  factory Float32x4.fromFloat64x2(Float64x2 xy) =>
      _Float32x4._(_toSingle(xy.x), _toSingle(xy.y), 0.0, 0.0);
}

@patch
final class _Float32x4 {
  final double _x, _y, _z, _w;
  _Float32x4._(this._x, this._y, this._z, this._w);

  /// Each lane of this and [other] through [f], rounded.
  Float32x4 _each(Float32x4 other, double Function(double, double) f) =>
      Float32x4(f(_x, other.x), f(_y, other.y), f(_z, other.z), f(_w, other.w));

  Float32x4 _map(double Function(double) f) =>
      Float32x4(f(_x), f(_y), f(_z), f(_w));

  Int32x4 _test(Float32x4 other, bool Function(double, double) f) =>
      Int32x4.bool(
        f(_x, other.x),
        f(_y, other.y),
        f(_z, other.z),
        f(_w, other.w),
      );

  @patch
  Float32x4 operator +(Float32x4 other) => _each(other, (a, b) => a + b);
  @patch
  Float32x4 operator -() => _map((a) => -a);
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
  Float32x4 abs() => _map((a) => a.abs());
  @patch
  Float32x4 clamp(Float32x4 lowerLimit, Float32x4 upperLimit) =>
      max(lowerLimit).min(upperLimit);
  @patch
  double get x => _x;
  @patch
  double get y => _y;
  @patch
  double get z => _z;
  @patch
  double get w => _w;
  @patch
  int get signMask =>
      _signOf(_x) | _signOf(_y) << 1 | _signOf(_z) << 2 | _signOf(_w) << 3;

  @patch
  Float32x4 shuffle(int mask) {
    _checkMask(mask);
    return _Float32x4._(
      _lane(mask & 3, _x, _y, _z, _w),
      _lane(mask >> 2 & 3, _x, _y, _z, _w),
      _lane(mask >> 4 & 3, _x, _y, _z, _w),
      _lane(mask >> 6 & 3, _x, _y, _z, _w),
    );
  }

  @patch
  Float32x4 shuffleMix(Float32x4 zw, int mask) {
    _checkMask(mask);
    return _Float32x4._(
      _lane(mask & 3, _x, _y, _z, _w),
      _lane(mask >> 2 & 3, _x, _y, _z, _w),
      _lane(mask >> 4 & 3, zw.x, zw.y, zw.z, zw.w),
      _lane(mask >> 6 & 3, zw.x, zw.y, zw.z, zw.w),
    );
  }

  @patch
  Float32x4 _withX(double x) => _Float32x4._(_toSingle(x), _y, _z, _w);
  @patch
  Float32x4 _withY(double y) => _Float32x4._(_x, _toSingle(y), _z, _w);
  @patch
  Float32x4 _withZ(double z) => _Float32x4._(_x, _y, _toSingle(z), _w);
  @patch
  Float32x4 _withW(double w) => _Float32x4._(_x, _y, _z, _toSingle(w));
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
  factory Int32x4.fromFloat32x4Bits(Float32x4 x) => _Int32x4._(
    _bitsOfSingle(x.x),
    _bitsOfSingle(x.y),
    _bitsOfSingle(x.z),
    _bitsOfSingle(x.w),
  );
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
    double one(int mask, double ifTrue, double ifFalse) => _singleOfBits(
      _bitsOfSingle(ifTrue) & mask | _bitsOfSingle(ifFalse) & ~mask,
    );
    return _Float32x4._(
      one(_x, trueValue.x, falseValue.x),
      one(_y, trueValue.y, falseValue.y),
      one(_z, trueValue.z, falseValue.z),
      one(_w, trueValue.w, falseValue.w),
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
  Float32x4 _getFloat32x4(int offsetInBytes) => Float32x4(
    _getFloat32(offsetInBytes),
    _getFloat32(offsetInBytes + 4),
    _getFloat32(offsetInBytes + 8),
    _getFloat32(offsetInBytes + 12),
  );
  @patch
  void _setFloat32x4(int offsetInBytes, Float32x4 value) {
    _setFloat32(offsetInBytes, value.x);
    _setFloat32(offsetInBytes + 4, value.y);
    _setFloat32(offsetInBytes + 8, value.z);
    _setFloat32(offsetInBytes + 12, value.w);
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
