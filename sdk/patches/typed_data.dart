import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../runtime/memory.dart';

@patch
class Int8List {
  @patch
  factory Int8List(int length) =>
      _NativeData.allocate(length, 1).buffer.asInt8List();
}

@patch
class Uint8List {
  @patch
  factory Uint8List(int length) => _NativeData.allocate(length, 1);
}

@patch
class Uint8ClampedList {
  @patch
  factory Uint8ClampedList(int length) =>
      _NativeData.allocate(length, 1).buffer.asUint8ClampedList();
}

@patch
class Int16List {
  @patch
  factory Int16List(int length) =>
      _NativeData.allocate(length, 2).buffer.asInt16List();
}

@patch
class Uint16List {
  @patch
  factory Uint16List(int length) =>
      _NativeData.allocate(length, 2).buffer.asUint16List();
}

@patch
class Int32List {
  @patch
  factory Int32List(int length) =>
      _NativeData.allocate(length, 4).buffer.asInt32List();
}

@patch
class Uint32List {
  @patch
  factory Uint32List(int length) =>
      _NativeData.allocate(length, 4).buffer.asUint32List();
}

@patch
class Int64List {
  @patch
  factory Int64List(int length) =>
      _NativeData.allocate(length, 8).buffer.asInt64List();
}

@patch
class Uint64List {
  @patch
  factory Uint64List(int length) =>
      _NativeData.allocate(length, 8).buffer.asUint64List();
}

@patch
class Float32List {
  @patch
  factory Float32List(int length) =>
      _NativeData.allocate(length, 4).buffer.asFloat32List();
}

@patch
class Float64List {
  @patch
  factory Float64List(int length) =>
      _NativeData.allocate(length, 8).buffer.asFloat64List();
}

TypedData _nativeStorage(TypedData? data, int offset, int size) {
  if (data == null) return ByteData(size);
  RangeError.checkValueInInterval(
    offset,
    0,
    data.lengthInBytes ~/ data.elementSizeInBytes,
    'offset',
  );
  final start = offset * data.elementSizeInBytes;
  if (data.lengthInBytes - start < size) {
    throw RangeError('TypedData is too small for the native view');
  }
  return ByteData.view(data.buffer, data.offsetInBytes + start, size);
}

int _nativeAddress(TypedData data) =>
    ((data.buffer as _ByteBuffer)._data as _NativeData)._address +
    data.offsetInBytes;

int _nativeListAddress(TypedData data, int index) {
  final list = data as _TypedListBase;
  return (list._typedData as _NativeData)._address +
      list.offsetInBytes +
      index * list.elementSizeInBytes;
}

ByteBuffer _nativeBuffer(
  Object owner,
  int address,
  int length,
  int elementSize,
) {
  RangeError.checkValueInInterval(
    length,
    0,
    0x7fffffffffffffff ~/ elementSize,
    'length',
  );
  return _NativeData(owner, address, length * elementSize).buffer;
}

Finalizable _nativeOwner(TypedData data) =>
    (data.buffer as _ByteBuffer)._data as Finalizable;

final class _NativeData(
  final Object _owner,
  final int _address,
  final int _byteLength,
) extends _TypedIntListBase
    with _TypedListMixin<int, Uint8List>, _Uint8ListCommonMixin
    implements Finalizable {
  factory allocate(int length, int width) {
    RangeError.checkNotNegative(length, 'length');
    const maximum = 0x0ffffffffffffff8 - ObjectHeader.fieldsOffset;
    final bytes = length > maximum ~/ width ? -1 : length * width;
    final owner = ByteStorage.allocate(bytes);
    return .new(
      owner,
      Memory.addressOf(owner) + ObjectHeader.fieldsOffset,
      bytes,
    );
  }

  @override
  int get length => _byteLength;
  @override
  int get elementSizeInBytes => 1;

  @override
  int operator [](int index) =>
      _getUint8(_typedDataIndexCheck(this, index, length));
  @override
  void operator []=(int index, int value) =>
      _setUint8(_typedDataIndexCheck(this, index, length), value);
}

@patch
class _TypedListBase {
  bool get _writable => true;

  void _copyBytes(
    int start,
    int count,
    _TypedListBase from,
    int skipCount,
    int width,
  ) {
    if (!_writable)
      throw UnsupportedError('Cannot modify an unmodifiable list');
    Memory.copyBytes(
      Pointer.fromAddress(
        (_typedData as _NativeData)._address + offsetInBytes + start * width,
      ),
      Pointer.fromAddress(
        (from._typedData as _NativeData)._address +
            from.offsetInBytes +
            skipCount * width,
      ),
      count * width,
    );
    Memory.keepAlive(from);
    Memory.keepAlive(this);
  }

  @patch
  void _setClampedRange(
    int start,
    int count,
    _TypedListBase from,
    int skipOffset,
  ) {
    if (!_writable)
      throw UnsupportedError('Cannot modify an unmodifiable list');
    final source = from as List<int>, target = this as List<int>;
    final backward =
        (_typedData as _NativeData)._address + offsetInBytes + start >
        (from._typedData as _NativeData)._address +
            from.offsetInBytes +
            skipOffset;
    for (var n = 0; n < count; n++) {
      final i = backward ? count - n - 1 : n;
      target[start + i] = source[skipOffset + i];
    }
  }

  @patch
  void _memMove1(int start, int count, _TypedListBase from, int skipCount) =>
      _copyBytes(start, count, from, skipCount, 1);

  @patch
  void _memMove2(int start, int count, _TypedListBase from, int skipCount) =>
      _copyBytes(start, count, from, skipCount, 2);

  @patch
  void _memMove4(int start, int count, _TypedListBase from, int skipCount) =>
      _copyBytes(start, count, from, skipCount, 4);

  @patch
  void _memMove8(int start, int count, _TypedListBase from, int skipCount) =>
      _copyBytes(start, count, from, skipCount, 8);
}

@patch
class _TypedList {
  int _readBits(int offset, int width) {
    final data = this as _NativeData;
    var bits = 0;
    for (var i = 0; i < width; i++) {
      bits |=
          Pointer<Uint8>.fromAddress(data._address + offset + i).value <<
          (i * 8);
    }
    Memory.keepAlive(data);
    return bits;
  }

  void _writeBits(int offset, int width, int value) {
    final data = this as _NativeData;
    for (var i = 0; i < width; i++) {
      Pointer<Uint8>.fromAddress(data._address + offset + i).value =
          value >>> (i * 8);
    }
    Memory.keepAlive(data);
  }

  @patch
  int _getInt8(int offsetInBytes) => _readBits(offsetInBytes, 1).toSigned(8);
  @patch
  void _setInt8(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 1, value);

  @patch
  int _getUint8(int offsetInBytes) => _readBits(offsetInBytes, 1);
  @patch
  void _setUint8(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 1, value);

  @patch
  int _getInt16(int offsetInBytes) => _readBits(offsetInBytes, 2).toSigned(16);
  @patch
  void _setInt16(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 2, value);

  @patch
  int _getUint16(int offsetInBytes) => _readBits(offsetInBytes, 2);
  @patch
  void _setUint16(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 2, value);

  @patch
  int _getInt32(int offsetInBytes) => _readBits(offsetInBytes, 4).toSigned(32);
  @patch
  void _setInt32(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 4, value);

  @patch
  int _getUint32(int offsetInBytes) => _readBits(offsetInBytes, 4);
  @patch
  void _setUint32(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 4, value);

  @patch
  int _getInt64(int offsetInBytes) => _readBits(offsetInBytes, 8);
  @patch
  void _setInt64(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 8, value);

  @patch
  int _getUint64(int offsetInBytes) => _readBits(offsetInBytes, 8);
  @patch
  void _setUint64(int offsetInBytes, int value) =>
      _writeBits(offsetInBytes, 8, value);

  @patch
  double _getFloat32(int offsetInBytes) =>
      Memory.float32FromBits(_readBits(offsetInBytes, 4));
  @patch
  void _setFloat32(int offsetInBytes, double value) =>
      _writeBits(offsetInBytes, 4, Memory.float32Bits(value));

  @patch
  double _getFloat64(int offsetInBytes) =>
      Memory.float64FromBits(_readBits(offsetInBytes, 8));
  @patch
  void _setFloat64(int offsetInBytes, double value) =>
      _writeBits(offsetInBytes, 8, Memory.float64Bits(value));
}

@patch
class _TypedListView._storage(
  final _TypedList _storageData,
  final int _storageOffset,
  final int _storageLength, {
  final bool _writable = true,
}) {
  this {
    _checkView(
      _storageData,
      _storageOffset,
      _storageLength,
      elementSizeInBytes,
    );
  }
  @patch
  _TypedList get _typedData => _storageData;
  @patch
  int get offsetInBytes => _storageOffset;
  @override
  int get length => _storageLength;
}

@patch
class _TypedIntListViewBase._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();
}

@patch
class _TypedDoubleListViewBase._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();
}

// Abstract SDK view bases also require initialized storage constructors.
@patch
class _TypedFloat32x4ListViewBase._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();
}

@patch
class _TypedInt32x4ListViewBase._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();
}

@patch
class _TypedFloat64x2ListViewBase._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();
}

@patch
class _Int8ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Int8ArrayView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getInt8(
    offsetInBytes + _typedDataIndexCheck(this, index, length),
  );
}

@patch
class _UnmodifiableInt8ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableInt8ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Uint8ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Uint8ArrayView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getUint8(
    offsetInBytes + _typedDataIndexCheck(this, index, length),
  );
}

@patch
class _UnmodifiableUint8ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableUint8ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Uint8ClampedArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Uint8ClampedArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getUint8(
    offsetInBytes + _typedDataIndexCheck(this, index, length),
  );
}

@patch
class _UnmodifiableUint8ClampedArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableUint8ClampedArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Int16ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Int16ArrayView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getInt16(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 2,
  );
}

@patch
class _UnmodifiableInt16ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableInt16ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Uint16ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Uint16ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getUint16(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 2,
  );
}

@patch
class _UnmodifiableUint16ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableUint16ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Int32ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Int32ArrayView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getInt32(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 4,
  );
}

@patch
class _UnmodifiableInt32ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableInt32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Uint32ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Uint32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getUint32(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 4,
  );
}

@patch
class _UnmodifiableUint32ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableUint32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Int64ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Int64ArrayView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getInt64(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 8,
  );
}

@patch
class _UnmodifiableInt64ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableInt64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Uint64ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Uint64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  int operator [](int index) => _typedData._getUint64(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 8,
  );
}

@patch
class _UnmodifiableUint64ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableUint64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Float32ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Float32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  double operator [](int index) => _typedData._getFloat32(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 4,
  );
}

@patch
class _UnmodifiableFloat32ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableFloat32ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _Float64ArrayView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength, {
  super.writable,
}) {
  this : super._storage();

  @patch
  factory _Float64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);

  @patch
  double operator [](int index) => _typedData._getFloat64(
    offsetInBytes + _typedDataIndexCheck(this, index, length) * 8,
  );
}

@patch
class _UnmodifiableFloat64ArrayView._storage(
  _TypedList data,
  int offset,
  int length,
) {
  this : super._storage(data, offset, length, writable: false);

  @patch
  factory _UnmodifiableFloat64ArrayView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

@patch
class _ByteDataView._storage(
  final _TypedList _storageData,
  final int _storageOffset,
  final int _storageLength,
) {
  this {
    _checkView(_storageData, _storageOffset, _storageLength, 1);
  }
  @patch
  factory _ByteDataView._(_TypedList buffer, int offsetInBytes, int length) =>
      ._storage(buffer, offsetInBytes, length);
  @patch
  _TypedList get _typedData => _storageData;
  @patch
  int get offsetInBytes => _storageOffset;
  @patch
  int get length => _storageLength;
}

@patch
class _UnmodifiableByteDataView._storage(
  super.storageData,
  super.storageOffset,
  super.storageLength,
) {
  this : super._storage();
  @patch
  factory _UnmodifiableByteDataView._(
    _TypedList buffer,
    int offsetInBytes,
    int length,
  ) => ._storage(buffer, offsetInBytes, length);
}

void _checkView(_TypedList data, int offset, int length, int width) {
  // Validate element counts before multiplication can wrap at native word width.
  RangeError.checkValueInInterval(
    offset,
    0,
    data.lengthInBytes,
    'offsetInBytes',
  );
  RangeError.checkValueInInterval(
    length,
    0,
    (data.lengthInBytes - offset) ~/ width,
    'length',
  );
  _offsetAlignmentCheck(offset, width);
}

@patch
mixin _TypedListMixin<E, L extends List<E>> {
  @patch
  @pragma(
    'dartc:patch',
    'specification: TypedDataList addition retains numeric typed storage',
  )
  List<E> operator +(List<E> other) {
    // The public typed-data contract retains typed storage for numeric operands.
    final List<E> result;
    if (this is TypedDataList<int> && other is TypedDataList<int>) {
      result = Int64List(length + other.length) as List<E>;
    } else if (this is TypedDataList<double> &&
        other is TypedDataList<double>) {
      result = Float64List(length + other.length) as List<E>;
    } else {
      return [...this, ...other];
    }
    result.setRange(0, length, this);
    result.setRange(length, result.length, other);
    return result;
  }
}
