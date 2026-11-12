import 'dart:collection' show ListBase;
import 'dart:_internal' show FixedLengthListMixin;
import 'dart:math' show Random;

import '../../../layout/memory.dart';
import '../memory.dart';

@patch
class ByteData {
  @patch
  factory ByteData(int length) =>
      _Buffer.allocate(_byteLength(length, 1)).asByteData();
}

@patch
class Int8List {
  @patch
  factory Int8List(int length) =>
      _Buffer.allocate(_byteLength(length, 1)).asInt8List();
  @patch
  factory Int8List.fromList(List<int> elements) =>
      _fill(Int8List(elements.length), elements);
}

@patch
class Uint8List {
  @patch
  factory Uint8List(int length) =>
      _Buffer.allocate(_byteLength(length, 1)).asUint8List();
  @patch
  factory Uint8List.fromList(List<int> elements) =>
      _fill(Uint8List(elements.length), elements);
}

@patch
class Uint8ClampedList {
  @patch
  factory Uint8ClampedList(int length) =>
      _Buffer.allocate(_byteLength(length, 1)).asUint8ClampedList();
  @patch
  factory Uint8ClampedList.fromList(List<int> elements) =>
      _fill(Uint8ClampedList(elements.length), elements);
}

@patch
class Int16List {
  @patch
  factory Int16List(int length) =>
      _Buffer.allocate(_byteLength(length, 2)).asInt16List();
  @patch
  factory Int16List.fromList(List<int> elements) =>
      _fill(Int16List(elements.length), elements);
}

@patch
class Uint16List {
  @patch
  factory Uint16List(int length) =>
      _Buffer.allocate(_byteLength(length, 2)).asUint16List();
  @patch
  factory Uint16List.fromList(List<int> elements) =>
      _fill(Uint16List(elements.length), elements);
}

@patch
class Int32List {
  @patch
  factory Int32List(int length) =>
      _Buffer.allocate(_byteLength(length, 4)).asInt32List();
  @patch
  factory Int32List.fromList(List<int> elements) =>
      _fill(Int32List(elements.length), elements);
}

@patch
class Uint32List {
  @patch
  factory Uint32List(int length) =>
      _Buffer.allocate(_byteLength(length, 4)).asUint32List();
  @patch
  factory Uint32List.fromList(List<int> elements) =>
      _fill(Uint32List(elements.length), elements);
}

@patch
class Int64List {
  @patch
  factory Int64List(int length) =>
      _Buffer.allocate(_byteLength(length, 8)).asInt64List();
  @patch
  factory Int64List.fromList(List<int> elements) =>
      _fill(Int64List(elements.length), elements);
}

@patch
class Uint64List {
  @patch
  factory Uint64List(int length) =>
      _Buffer.allocate(_byteLength(length, 8)).asUint64List();
  @patch
  factory Uint64List.fromList(List<int> elements) =>
      _fill(Uint64List(elements.length), elements);
}

@patch
class Float32List {
  @patch
  factory Float32List(int length) =>
      _Buffer.allocate(_byteLength(length, 4)).asFloat32List();
  @patch
  factory Float32List.fromList(List<double> elements) =>
      _fill(Float32List(elements.length), elements);
}

@patch
class Float64List {
  @patch
  factory Float64List(int length) =>
      _Buffer.allocate(_byteLength(length, 8)).asFloat64List();
  @patch
  factory Float64List.fromList(List<double> elements) =>
      _fill(Float64List(elements.length), elements);
}

int _byteLength(int count, int bytes) {
  RangeError.checkNotNegative(count, 'length');
  if (count > (0x0ffffffffffffff8 - ObjectHeader.fieldsOffset) ~/ bytes) {
    return -1;
  }
  return count * bytes;
}

L _fill<E, L extends List<E>>(L result, List<E> source) {
  for (var i = 0; i < source.length; i++) {
    result[i] = source[i];
  }
  return result;
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
    (data.buffer as _Buffer)._address + data.offsetInBytes;

ByteBuffer _nativeBuffer(Object owner, int address, int length) =>
    _Buffer(owner, address, length);

enum _Element(
  final int bytes, {
  final bool signed = false,
  final bool floating = false,
  final bool clamped = false,
}) {
  int8(1, signed: true),
  uint8(1),
  uint8Clamped(1, clamped: true),
  int16(2, signed: true),
  uint16(2),
  int32(4, signed: true),
  uint32(4),
  int64(8, signed: true),
  uint64(8),
  float32(4, signed: true, floating: true),
  float64(8, signed: true, floating: true),
}

final class _Buffer(
  final Object _owner,
  final int _address,
  final int lengthInBytes, {
  final bool _writable = true,
}) implements ByteBuffer {
  factory allocate(int length) {
    final data = ByteStorage.allocate(length);
    return .new(
      data,
      Memory.addressOf(data) + ObjectHeader.fieldsOffset,
      length,
    );
  }

  _Buffer get _readOnly =>
      _writable ? .new(_owner, _address, lengthInBytes, writable: false) : this;

  int _length(int offset, int? length, int bytes) {
    RangeError.checkValueInInterval(offset, 0, lengthInBytes, 'offsetInBytes');
    if (offset % bytes != 0) throw ArgumentError.value(offset, 'offsetInBytes');
    final available = (lengthInBytes - offset) ~/ bytes;
    if (length == null) return available;
    RangeError.checkValueInInterval(length, 0, available, 'length');
    return length;
  }

  void _checkWritable() {
    if (!_writable)
      throw UnsupportedError('Cannot modify an unmodifiable view');
  }

  int _read(int offset, int width, Endian endian) {
    var result = 0;
    for (var i = 0; i < width; i++) {
      final shift = (endian == Endian.little ? i : width - i - 1) * 8;
      result |= Memory.readByte(_address + offset + i) << shift;
    }
    Memory.keepAlive(this);
    return result;
  }

  void _write(int offset, int width, int value, Endian endian) {
    _checkWritable();
    for (var i = 0; i < width; i++) {
      final shift = (endian == Endian.little ? i : width - i - 1) * 8;
      Memory.writeByte(_address + offset + i, value >>> shift);
    }
    Memory.keepAlive(this);
  }

  @override
  ByteData asByteData([int offsetInBytes = 0, int? length]) =>
      _ByteData(this, offsetInBytes, _length(offsetInBytes, length, 1));
  @override
  Int8List asInt8List([int offsetInBytes = 0, int? length]) =>
      _Int8List(this, offsetInBytes, _length(offsetInBytes, length, 1));
  @override
  Uint8List asUint8List([int offsetInBytes = 0, int? length]) =>
      _Uint8List(this, offsetInBytes, _length(offsetInBytes, length, 1));
  @override
  Uint8ClampedList asUint8ClampedList([int offsetInBytes = 0, int? length]) =>
      _Uint8ClampedList(this, offsetInBytes, _length(offsetInBytes, length, 1));
  @override
  Int16List asInt16List([int offsetInBytes = 0, int? length]) =>
      _Int16List(this, offsetInBytes, _length(offsetInBytes, length, 2));
  @override
  Uint16List asUint16List([int offsetInBytes = 0, int? length]) =>
      _Uint16List(this, offsetInBytes, _length(offsetInBytes, length, 2));
  @override
  Int32List asInt32List([int offsetInBytes = 0, int? length]) =>
      _Int32List(this, offsetInBytes, _length(offsetInBytes, length, 4));
  @override
  Uint32List asUint32List([int offsetInBytes = 0, int? length]) =>
      _Uint32List(this, offsetInBytes, _length(offsetInBytes, length, 4));
  @override
  Int64List asInt64List([int offsetInBytes = 0, int? length]) =>
      _Int64List(this, offsetInBytes, _length(offsetInBytes, length, 8));
  @override
  Uint64List asUint64List([int offsetInBytes = 0, int? length]) =>
      _Uint64List(this, offsetInBytes, _length(offsetInBytes, length, 8));
  @override
  Float32List asFloat32List([int offsetInBytes = 0, int? length]) =>
      _Float32List(this, offsetInBytes, _length(offsetInBytes, length, 4));
  @override
  Float64List asFloat64List([int offsetInBytes = 0, int? length]) =>
      _Float64List(this, offsetInBytes, _length(offsetInBytes, length, 8));
  @override
  external Float32x4List asFloat32x4List([int offsetInBytes = 0, int? length]);
  @override
  external Int32x4List asInt32x4List([int offsetInBytes = 0, int? length]);
  @override
  external Float64x2List asFloat64x2List([int offsetInBytes = 0, int? length]);
}

abstract class _TypedList<E extends num, L extends List<E>>(
  final _Buffer buffer,
  final int offsetInBytes,
  final int length,
  final _Element _kind,
) extends ListBase<E> with FixedLengthListMixin<E> implements TypedData {
  @override
  int get elementSizeInBytes => _kind.bytes;
  @override
  int get lengthInBytes => length * elementSizeInBytes;
  L _view(_Buffer buffer, int offset, int length);

  int _offset(int index) {
    if (index < 0 || index >= length) {
      throw IndexError.withLength(
        index,
        length,
        indexable: this,
        name: 'index',
      );
    }
    return offsetInBytes + index * elementSizeInBytes;
  }

  @override
  E operator [](int index) {
    var bits = buffer._read(_offset(index), _kind.bytes, Endian.little);
    if (_kind.floating) {
      return (_kind.bytes == 4
              ? Memory.float32FromBits(bits)
              : Memory.float64FromBits(bits))
          as E;
    }
    if (_kind.signed && _kind.bytes < 8) {
      final shift = 64 - _kind.bytes * 8;
      bits = (bits << shift) >> shift;
    }
    return bits as E;
  }

  @override
  void operator []=(int index, E value) {
    buffer._checkWritable();
    final offset = _offset(index);
    final int bits;
    if (_kind.floating) {
      bits = _kind.bytes == 4
          ? Memory.float32Bits(value as double)
          : Memory.float64Bits(value as double);
    } else {
      final integer = value as int;
      bits = _kind.clamped
          ? (integer < 0
                ? 0
                : integer > 255
                ? 255
                : integer)
          : integer;
    }
    buffer._write(offset, _kind.bytes, bits, Endian.little);
  }

  L asUnmodifiableView() => _view(buffer._readOnly, offsetInBytes, length);

  @override
  List<E> operator +(List<E> other) {
    if (other is! _TypedList<E, List<E>>) return super + other;
    final total = length + other.length;
    final result =
        (_kind.floating ? Float64List(total) : Int64List(total)) as List<E>;
    result.setRange(0, length, this);
    result.setRange(length, total, other);
    return result;
  }

  @override
  L sublist(int start, [int? end]) {
    final limit = RangeError.checkValidRange(start, end, length);
    final result = _view(
      _Buffer.allocate((limit - start) * elementSizeInBytes),
      0,
      limit - start,
    );
    for (var i = start; i < limit; i++) {
      result[i - start] = this[i];
    }
    return result;
  }

  @override
  void setRange(int start, int end, Iterable<E> iterable, [int skipCount = 0]) {
    RangeError.checkValidRange(start, end, length);
    RangeError.checkNotNegative(skipCount, 'skipCount');
    final count = end - start;
    if (iterable is _TypedList<E, List<E>>) {
      if (iterable.length - skipCount < count)
        throw StateError('Too few elements');
      if (count == 0) return;
      buffer._checkWritable();
    }
    if (iterable is _TypedList<E, List<E>> && iterable._kind == _kind) {
      Memory.copyBytes(
        buffer._address + offsetInBytes + start * elementSizeInBytes,
        iterable.buffer._address +
            iterable.offsetInBytes +
            skipCount * elementSizeInBytes,
        count * elementSizeInBytes,
      );
      Memory.keepAlive(iterable);
      Memory.keepAlive(this);
      return;
    }
    if (iterable is _TypedList<E, List<E>> &&
        identical(buffer._owner, iterable.buffer._owner)) {
      iterable = iterable.sublist(skipCount, skipCount + end - start);
      skipCount = 0;
    }
    super.setRange(start, end, iterable, skipCount);
  }

  @override
  void setAll(int index, Iterable<E> iterable) {
    buffer._checkWritable();
    super.setAll(index, iterable);
  }

  @override
  void fillRange(int start, int end, [E? fillValue]) {
    buffer._checkWritable();
    super.fillRange(start, end, fillValue);
  }

  @override
  void sort([int Function(E, E)? compare]) {
    buffer._checkWritable();
    super.sort(compare);
  }

  @override
  void shuffle([Random? random]) {
    buffer._checkWritable();
    super.shuffle(random);
  }
}

final class _Int8List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Int8List>
    implements Int8List {
  this : super(buffer, offset, length, .int8);
  @override
  Int8List _view(_Buffer buffer, int offset, int length) =>
      _Int8List(buffer, offset, length);
}

final class _Uint8List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Uint8List>
    implements Uint8List {
  this : super(buffer, offset, length, .uint8);
  @override
  Uint8List _view(_Buffer buffer, int offset, int length) =>
      _Uint8List(buffer, offset, length);
}

final class _Uint8ClampedList(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Uint8ClampedList>
    implements Uint8ClampedList {
  this : super(buffer, offset, length, .uint8Clamped);
  @override
  Uint8ClampedList _view(_Buffer buffer, int offset, int length) =>
      _Uint8ClampedList(buffer, offset, length);
}

final class _Int16List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Int16List>
    implements Int16List {
  this : super(buffer, offset, length, .int16);
  @override
  Int16List _view(_Buffer buffer, int offset, int length) =>
      _Int16List(buffer, offset, length);
}

final class _Uint16List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Uint16List>
    implements Uint16List {
  this : super(buffer, offset, length, .uint16);
  @override
  Uint16List _view(_Buffer buffer, int offset, int length) =>
      _Uint16List(buffer, offset, length);
}

final class _Int32List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Int32List>
    implements Int32List {
  this : super(buffer, offset, length, .int32);
  @override
  Int32List _view(_Buffer buffer, int offset, int length) =>
      _Int32List(buffer, offset, length);
}

final class _Uint32List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Uint32List>
    implements Uint32List {
  this : super(buffer, offset, length, .uint32);
  @override
  Uint32List _view(_Buffer buffer, int offset, int length) =>
      _Uint32List(buffer, offset, length);
}

final class _Int64List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Int64List>
    implements Int64List {
  this : super(buffer, offset, length, .int64);
  @override
  Int64List _view(_Buffer buffer, int offset, int length) =>
      _Int64List(buffer, offset, length);
}

final class _Uint64List(_Buffer buffer, int offset, int length)
    extends _TypedList<int, Uint64List>
    implements Uint64List {
  this : super(buffer, offset, length, .uint64);
  @override
  Uint64List _view(_Buffer buffer, int offset, int length) =>
      _Uint64List(buffer, offset, length);
}

final class _Float32List(_Buffer buffer, int offset, int length)
    extends _TypedList<double, Float32List>
    implements Float32List {
  this : super(buffer, offset, length, .float32);
  @override
  Float32List _view(_Buffer buffer, int offset, int length) =>
      _Float32List(buffer, offset, length);
}

final class _Float64List(_Buffer buffer, int offset, int length)
    extends _TypedList<double, Float64List>
    implements Float64List {
  this : super(buffer, offset, length, .float64);
  @override
  Float64List _view(_Buffer buffer, int offset, int length) =>
      _Float64List(buffer, offset, length);
}

final class _ByteData(
  final _Buffer buffer,
  final int offsetInBytes,
  final int lengthInBytes,
) implements ByteData {
  @override
  int get elementSizeInBytes => 1;
  @override
  ByteData asUnmodifiableView() =>
      _ByteData(buffer._readOnly, offsetInBytes, lengthInBytes);
  int _offset(int offset, int bytes) {
    RangeError.checkValueInInterval(
      offset,
      0,
      lengthInBytes - bytes,
      'byteOffset',
    );
    return offsetInBytes + offset;
  }

  int _read(int offset, int bytes, Endian endian, bool signed) {
    final bits = buffer._read(_offset(offset, bytes), bytes, endian);
    final shift = 64 - bytes * 8;
    return signed ? (bits << shift) >> shift : bits;
  }

  void _write(int offset, int bytes, int value, Endian endian) {
    buffer._checkWritable();
    buffer._write(_offset(offset, bytes), bytes, value, endian);
  }

  @override
  int getInt8(int byteOffset) => _read(byteOffset, 1, Endian.little, true);
  @override
  void setInt8(int byteOffset, int value) =>
      _write(byteOffset, 1, value, Endian.little);
  @override
  int getUint8(int byteOffset) => _read(byteOffset, 1, Endian.little, false);
  @override
  void setUint8(int byteOffset, int value) =>
      _write(byteOffset, 1, value, Endian.little);
  @override
  int getInt16(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 2, endian, true);
  @override
  void setInt16(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 2, value, endian);
  @override
  int getUint16(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 2, endian, false);
  @override
  void setUint16(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 2, value, endian);
  @override
  int getInt32(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 4, endian, true);
  @override
  void setInt32(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 4, value, endian);
  @override
  int getUint32(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 4, endian, false);
  @override
  void setUint32(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 4, value, endian);
  @override
  int getInt64(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 8, endian, true);
  @override
  void setInt64(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 8, value, endian);
  @override
  int getUint64(int byteOffset, [Endian endian = Endian.big]) =>
      _read(byteOffset, 8, endian, false);
  @override
  void setUint64(int byteOffset, int value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 8, value, endian);
  @override
  double getFloat32(int byteOffset, [Endian endian = Endian.big]) =>
      Memory.float32FromBits(_read(byteOffset, 4, endian, false));
  @override
  void setFloat32(int byteOffset, double value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 4, Memory.float32Bits(value), endian);
  @override
  double getFloat64(int byteOffset, [Endian endian = Endian.big]) =>
      Memory.float64FromBits(_read(byteOffset, 8, endian, false));
  @override
  void setFloat64(int byteOffset, double value, [Endian endian = Endian.big]) =>
      _write(byteOffset, 8, Memory.float64Bits(value), endian);
}
