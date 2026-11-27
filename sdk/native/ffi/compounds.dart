// Structs, unions and arrays.
import 'dart:_heap/machine.dart' show load8, store8;
import 'dart:_heap/objects.dart' show dataAddress;

/// Where what [base] is, a pointer, a struct or typed data, starts.
int _startOf(Object base) {
  if (base is Pointer) return base._address;
  if (base is _Compound) {
    return _startOf(base._typedDataBase) + base._offsetInBytes;
  }
  return dataAddress(base);
}

Object _baseOf(_Compound compound) => compound._typedDataBase;

int _offsetOf(_Compound compound) => compound._offsetInBytes;

/// Memory for [size] bytes, which are 0.
Uint8List _newMemory(int size) => Uint8List(size);

/// A copy of the [size] bytes of [compound].
Uint8List _copyOf(Object compound, int size) {
  final copy = Uint8List(size);
  _copyBytes(_startOf(copy), _startOf(compound), size);
  return copy;
}

/// Copies [count] bytes [from] one address [to] another.
void _copyBytes(int to, int from, int count) {
  for (var i = 0; i < count; i++) {
    store8(to + i, load8(from + i));
  }
}

/// Copies the [count] bytes of [from] to what starts [offset] bytes after
/// [to].
void _assignCompound(Object to, int offset, Object from, int count) =>
    _copyBytes(_startOf(to) + offset, _startOf(from), count);

/// An array of [sizes] dimensions that starts [offset] bytes after [base].
Array<T> _newArray<T extends NativeType>(
  Object base,
  int offset,
  bool isVariable,
  List<Object?> sizes,
) {
  final all = [for (final size in sizes) unsafeCast<int>(size)];
  return Array<T>._(base, offset, all.first, isVariable, all.sublist(1));
}

/// Checks [index], then tells where the element of [array] is, which takes
/// [size] bytes.
int _elementOffset(Array array, int index, int size) {
  array._checkIndex(index);
  return array._offsetInBytes + index * size;
}

Array<T> _innerArray<T extends NativeType>(
  Array<Array<T>> array,
  int index,
  int size,
) => _ArrayArrayList<T>(array, size)[index];

void _setInnerArray<T extends NativeType>(
  Array<Array<T>> array,
  int index,
  Array<T> value,
  int size,
) {
  _ArrayArrayList<T>(array, size)[index] = value;
}

List<Array<T>> _innerArrays<T extends NativeType>(
  Array<Array<T>> array,
  int size,
) => _ArrayArrayList<T>(array, size);

List<T> _compoundsOf<T extends NativeType>(
  Array<T> array,
  int size,
  T Function(Object base, int offset) make,
) => _ArrayList<T>(array, size, make);

/// The integers of [array], of [size] bytes each.
List<int> _integersOf(Array array, int size, bool isSigned) =>
    _Integers(array, size, isSigned);

class _Integers with ListMixin<int>, FixedLengthListMixin<int> {
  final Array _array;
  final int _size;
  final bool _isSigned;

  _Integers(this._array, this._size, this._isSigned);

  int get length => _array._size;

  int operator [](int index) {
    final base = _array._typedDataBase;
    final at = _elementOffset(_array, index, _size);
    return switch (_size) {
      1 => _isSigned ? _loadInt8(base, at) : _loadUint8(base, at),
      2 => _isSigned ? _loadInt16(base, at) : _loadUint16(base, at),
      4 => _isSigned ? _loadInt32(base, at) : _loadUint32(base, at),
      _ => _loadInt64(base, at),
    };
  }

  operator []=(int index, int value) {
    final base = _array._typedDataBase;
    final at = _elementOffset(_array, index, _size);
    switch (_size) {
      case 1:
        _storeInt8(base, at, value);
      case 2:
        _storeInt16(base, at, value);
      case 4:
        _storeInt32(base, at, value);
      default:
        _storeInt64(base, at, value);
    }
  }
}

/// A pointer to where [base] starts, which keeps that.
Pointer<T> _pointerTo<T extends NativeType>(Object base) =>
    Pointer<Never>._(_startOf(base)).._owner = base;

/// A pointer to [offset] bytes after where [base] starts, which keeps that.
Pointer<T> _pointerInto<T extends NativeType>(Object base, int offset) =>
    Pointer<Never>._(_startOf(base) + offset).._owner = base;

int _elementSize(TypedData data) => data.elementSizeInBytes;

/// Where the struct of [size] bytes is in [data], from an element on.
int _checkData(TypedData data, int element, int size) {
  final start = data.elementSizeInBytes * element;
  if (data.lengthInBytes < start + size) {
    throw RangeError.range(
      data.lengthInBytes,
      size + start,
      null,
      'typedData.lengthInBytes',
      'The typed list is not large enough',
    );
  }
  return start;
}

Pointer<T> _allocateWith<T extends NativeType>(
  Allocator allocator,
  int byteCount,
) => allocator.allocate<T>(byteCount);

/// The address of the function called [name] in [library].
int _lookupAddress(DynamicLibrary library, String name) =>
    library.lookup<NativeType>(name)._address;

/// Makes a struct or union that is [offset] bytes after [base].
typedef _MakeCompound = Object Function(Object base, int offset);
