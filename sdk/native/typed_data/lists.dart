import 'dart:_heap/machine.dart' show addressOf;
import 'dart:_heap/objects.dart'
    show
        lengthOf,
        loadInt8,
        loadUint8,
        loadInt16,
        loadUint16,
        loadInt32,
        loadUint32,
        loadInt64,
        loadFloat32,
        loadFloat64,
        newArray,
        storeInt8,
        storeUint8,
        storeInt16,
        storeUint16,
        storeInt32,
        storeUint32,
        storeInt64,
        storeFloat32,
        storeFloat64;

@patch
class _TypedListBase {
  @patch
  int get length => throw UnsupportedError('This typed data');

  @patch
  void _setClampedRange(
    int start,
    int count,
    _TypedListBase from,
    int skipOffset,
  ) {
    // Copies backwards where the parts may overlap that way.
    final to = this as List<int>, values = from as List<int>;
    if (skipOffset < start) {
      for (var i = count - 1; i >= 0; i--) {
        to[start + i] = values[skipOffset + i];
      }
    } else {
      for (var i = 0; i < count; i++) {
        to[start + i] = values[skipOffset + i];
      }
    }
  }

  /// Copies elements of [size] bytes, which may overlap.
  void _move(int start, int count, _TypedListBase from, int skip, int size) {
    final source = from._typedData, target = _typedData;
    final first = from.offsetInBytes + skip * size;
    final to = offsetInBytes + start * size, bytes = count * size;
    final isBackward = first < to;
    final isOutside = source._isOutside || target._isOutside;
    var copied = 0;
    if (!isOutside) {
      for (; copied + 8 <= bytes; copied += 8) {
        final at = isBackward ? bytes - 8 - copied : copied;
        storeInt64(target, to + at, loadInt64(source, first + at));
      }
    }
    for (; copied < bytes; copied++) {
      final at = isBackward ? bytes - 1 - copied : copied;
      if (isOutside) {
        target._setUint8(to + at, source._getUint8(first + at));
      } else {
        storeUint8(target, to + at, loadUint8(source, first + at));
      }
    }
  }

  @patch
  void _memMove1(int start, int count, _TypedListBase from, int skipCount) =>
      _move(start, count, from, skipCount, 1);

  @patch
  void _memMove2(int start, int count, _TypedListBase from, int skipCount) =>
      _move(start, count, from, skipCount, 2);

  @patch
  void _memMove4(int start, int count, _TypedListBase from, int skipCount) =>
      _move(start, count, from, skipCount, 4);

  @patch
  void _memMove8(int start, int count, _TypedListBase from, int skipCount) =>
      _move(start, count, from, skipCount, 8);

  @patch
  void _memMove16(int start, int count, _TypedListBase from, int skipCount) =>
      _move(start, count, from, skipCount, 16);
}

@patch
class _TypedList {
  /// Where the first byte is.
  int get _start => addressOf(this) + 24;

  /// Whether that is not in this object.
  bool get _isOutside => false;

  @patch
  int _getInt8(int offsetInBytes) => loadInt8(this, offsetInBytes);
  @patch
  void _setInt8(int offsetInBytes, int value) =>
      storeInt8(this, offsetInBytes, value);

  @patch
  int _getUint8(int offsetInBytes) => loadUint8(this, offsetInBytes);
  @patch
  void _setUint8(int offsetInBytes, int value) =>
      storeUint8(this, offsetInBytes, value);

  @patch
  int _getInt16(int offsetInBytes) => loadInt16(this, offsetInBytes);
  @patch
  void _setInt16(int offsetInBytes, int value) =>
      storeInt16(this, offsetInBytes, value);

  @patch
  int _getUint16(int offsetInBytes) => loadUint16(this, offsetInBytes);
  @patch
  void _setUint16(int offsetInBytes, int value) =>
      storeUint16(this, offsetInBytes, value);

  @patch
  int _getInt32(int offsetInBytes) => loadInt32(this, offsetInBytes);
  @patch
  void _setInt32(int offsetInBytes, int value) =>
      storeInt32(this, offsetInBytes, value);

  @patch
  int _getUint32(int offsetInBytes) => loadUint32(this, offsetInBytes);
  @patch
  void _setUint32(int offsetInBytes, int value) =>
      storeUint32(this, offsetInBytes, value);

  @patch
  int _getInt64(int offsetInBytes) => loadInt64(this, offsetInBytes);
  @patch
  void _setInt64(int offsetInBytes, int value) =>
      storeInt64(this, offsetInBytes, value);

  @patch
  double _getFloat32(int offsetInBytes) => loadFloat32(this, offsetInBytes);
  @patch
  void _setFloat32(int offsetInBytes, double value) =>
      storeFloat32(this, offsetInBytes, value);

  @patch
  double _getFloat64(int offsetInBytes) => loadFloat64(this, offsetInBytes);
  @patch
  void _setFloat64(int offsetInBytes, double value) =>
      storeFloat64(this, offsetInBytes, value);

  @patch
  int _getUint64(int offsetInBytes) => loadInt64(this, offsetInBytes);
  @patch
  void _setUint64(int offsetInBytes, int value) =>
      storeInt64(this, offsetInBytes, value);
}

@patch
class Int8List {
  @patch
  factory Int8List(int length) {
    _checkLength(length, 1);
    return newArray<_Int8List>(length);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Int8List {
  int get length => lengthOf(this);

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this));
    return loadInt8(this, index);
  }
}

@patch
class _Int8ArrayView {
  @patch
  _Int8ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt8(offsetInBytes + (index));
  }
}

@patch
class _UnmodifiableInt8ArrayView {
  @patch
  _UnmodifiableInt8ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._(buffer, offsetInBytes, length);
}

@patch
class Uint8List {
  @patch
  factory Uint8List(int length) {
    _checkLength(length, 1);
    return newArray<_Uint8List>(length);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Uint8List {
  int get length => lengthOf(this);

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this));
    return loadUint8(this, index);
  }
}

@patch
class _Uint8ArrayView {
  @patch
  _Uint8ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getUint8(offsetInBytes + (index));
  }
}

@patch
class _UnmodifiableUint8ArrayView {
  @patch
  _UnmodifiableUint8ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Uint8ClampedList {
  @patch
  factory Uint8ClampedList(int length) {
    _checkLength(length, 1);
    return newArray<_Uint8ClampedList>(length);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Uint8ClampedList {
  int get length => lengthOf(this);

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this));
    return loadUint8(this, index);
  }
}

@patch
class _Uint8ClampedArrayView {
  @patch
  _Uint8ClampedArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getUint8(offsetInBytes + (index));
  }
}

@patch
class _UnmodifiableUint8ClampedArrayView {
  @patch
  _UnmodifiableUint8ClampedArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Int16List {
  @patch
  factory Int16List(int length) {
    _checkLength(length, 2);
    return newArray<_Int16List>(length << 1);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Int16List {
  int get length => lengthOf(this) >> 1;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 1);
    return loadInt16(this, index << 1);
  }
}

@patch
class _Int16ArrayView {
  @patch
  _Int16ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt16(offsetInBytes + (index << 1));
  }
}

@patch
class _UnmodifiableInt16ArrayView {
  @patch
  _UnmodifiableInt16ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Uint16List {
  @patch
  factory Uint16List(int length) {
    _checkLength(length, 2);
    return newArray<_Uint16List>(length << 1);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Uint16List {
  int get length => lengthOf(this) >> 1;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 1);
    return loadUint16(this, index << 1);
  }
}

@patch
class _Uint16ArrayView {
  @patch
  _Uint16ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getUint16(offsetInBytes + (index << 1));
  }
}

@patch
class _UnmodifiableUint16ArrayView {
  @patch
  _UnmodifiableUint16ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Int32List {
  @patch
  factory Int32List(int length) {
    _checkLength(length, 4);
    return newArray<_Int32List>(length << 2);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Int32List {
  int get length => lengthOf(this) >> 2;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 2);
    return loadInt32(this, index << 2);
  }
}

@patch
class _Int32ArrayView {
  @patch
  _Int32ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt32(offsetInBytes + (index << 2));
  }
}

@patch
class _UnmodifiableInt32ArrayView {
  @patch
  _UnmodifiableInt32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Uint32List {
  @patch
  factory Uint32List(int length) {
    _checkLength(length, 4);
    return newArray<_Uint32List>(length << 2);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Uint32List {
  int get length => lengthOf(this) >> 2;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 2);
    return loadUint32(this, index << 2);
  }
}

@patch
class _Uint32ArrayView {
  @patch
  _Uint32ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getUint32(offsetInBytes + (index << 2));
  }
}

@patch
class _UnmodifiableUint32ArrayView {
  @patch
  _UnmodifiableUint32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Int64List {
  @patch
  factory Int64List(int length) {
    _checkLength(length, 8);
    return newArray<_Int64List>(length << 3);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Int64List {
  int get length => lengthOf(this) >> 3;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 3);
    return loadInt64(this, index << 3);
  }
}

@patch
class _Int64ArrayView {
  @patch
  _Int64ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt64(offsetInBytes + (index << 3));
  }
}

@patch
class _UnmodifiableInt64ArrayView {
  @patch
  _UnmodifiableInt64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Uint64List {
  @patch
  factory Uint64List(int length) {
    _checkLength(length, 8);
    return newArray<_Uint64List>(length << 3);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Uint64List {
  int get length => lengthOf(this) >> 3;

  @patch
  int operator [](int index) {
    _checkRead(index, lengthOf(this) >> 3);
    return loadInt64(this, index << 3);
  }
}

@patch
class _Uint64ArrayView {
  @patch
  _Uint64ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _typedData._getInt64(offsetInBytes + (index << 3));
  }
}

@patch
class _UnmodifiableUint64ArrayView {
  @patch
  _UnmodifiableUint64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Float32List {
  @patch
  factory Float32List(int length) {
    _checkLength(length, 4);
    return newArray<_Float32List>(length << 2);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Float32List {
  int get length => lengthOf(this) >> 2;

  @patch
  double operator [](int index) {
    _checkRead(index, lengthOf(this) >> 2);
    return loadFloat32(this, index << 2);
  }
}

@patch
class _Float32ArrayView {
  @patch
  _Float32ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  double operator [](int index) {
    _checkRead(index, length);
    return _typedData._getFloat32(offsetInBytes + (index << 2));
  }
}

@patch
class _UnmodifiableFloat32ArrayView {
  @patch
  _UnmodifiableFloat32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

@patch
class Float64List {
  @patch
  factory Float64List(int length) {
    _checkLength(length, 8);
    return newArray<_Float64List>(length << 3);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _Float64List {
  int get length => lengthOf(this) >> 3;

  @patch
  double operator [](int index) {
    _checkRead(index, lengthOf(this) >> 3);
    return loadFloat64(this, index << 3);
  }
}

@patch
class _Float64ArrayView {
  @patch
  _Float64ArrayView._(_TypedList buffer, int offsetInBytes, int length)
    : super._view(buffer, offsetInBytes, length);

  @patch
  double operator [](int index) {
    _checkRead(index, length);
    return _typedData._getFloat64(offsetInBytes + (index << 3));
  }
}

@patch
class _UnmodifiableFloat64ArrayView {
  @patch
  _UnmodifiableFloat64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) : super._(buffer, offsetInBytes, length);
}

void _checkRead(int index, int length) {
  if (index < 0 || index >= length) {
    throw RangeError.range(index, 0, length - 1, 'length');
  }
}

void _checkLength(int length, int size) {
  final most = 0x3fffffffffffffff ~/ size;
  if (length < 0) throw RangeError.range(length, 0, most, 'length');
  if (length > most) throw const OutOfMemoryError();
}

@patch
class _TypedListView {
  @patch
  final _TypedList _typedData;
  @patch
  final int offsetInBytes;
  final int length;

  _TypedListView._view(this._typedData, this.offsetInBytes, this.length);
}

@patch
class _ByteDataView {
  @patch
  final _TypedList _typedData;
  @patch
  final int offsetInBytes;
  @patch
  final int length;

  @patch
  _ByteDataView._(this._typedData, this.offsetInBytes, this.length);
}

@patch
class _UnmodifiableByteDataView {
  @patch
  _UnmodifiableByteDataView._(_TypedList buffer, int offsetInBytes, int length)
    : super._(buffer, offsetInBytes, length);
}

@patch
class _TypedIntListViewBase {
  _TypedIntListViewBase._view(super.data, super.offset, super.length)
    : super._view();
}

@patch
class _TypedDoubleListViewBase {
  _TypedDoubleListViewBase._view(super.data, super.offset, super.length)
    : super._view();
}

@patch
class _TypedFloat32x4ListViewBase {
  _TypedFloat32x4ListViewBase._view(super.data, super.offset, super.length)
    : super._view();
}

@patch
class _TypedInt32x4ListViewBase {
  _TypedInt32x4ListViewBase._view(super.data, super.offset, super.length)
    : super._view();
}

@patch
class _TypedFloat64x2ListViewBase {
  _TypedFloat64x2ListViewBase._view(super.data, super.offset, super.length)
    : super._view();
}
