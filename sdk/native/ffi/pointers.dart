// Memory outside of objects.
import 'dart:_heap/machine.dart'
    show load8, load32, load32Signed, load64, store8, store32, store64;
import 'dart:_heap/objects.dart'
    show
        listAt,
        load16,
        loadDouble,
        loadSingle,
        store16,
        storeDouble,
        storeSingle;

@patch
final class Pointer<T extends NativeType> {
  final int _address;

  // Like the official ones, pointers do not know what they point to.

  /// What is kept as long as this is, as it is where this points to.
  Object? _owner;

  Pointer._(this._address);

  @patch
  int get address => _address;

  String toString() => 'Pointer: address=${_hex(_address)}';
}

String _hex(int value) {
  var text = '', rest = value;
  do {
    text = '0123456789abcdef'[rest & 15] + text;
    rest >>>= 4;
  } while (rest != 0);
  return '0x$text';
}

@patch
Pointer<T> _fromAddress<T extends NativeType>(int ptr) => Pointer<Never>._(ptr);

/// The address of [pointer].
int _pointerAddress(Pointer pointer) => pointer._address;

@patch
int _loadInt8(Object typedDataBase, int offsetInBytes) =>
    (load8(_startOf(typedDataBase) + offsetInBytes) ^ 0x80) - 0x80;

@patch
int _loadInt16(Object typedDataBase, int offsetInBytes) =>
    (load16(_startOf(typedDataBase) + offsetInBytes) ^ 0x8000) - 0x8000;

@patch
int _loadInt32(Object typedDataBase, int offsetInBytes) =>
    load32Signed(_startOf(typedDataBase) + offsetInBytes);

@patch
int _loadInt64(Object typedDataBase, int offsetInBytes) =>
    load64(_startOf(typedDataBase) + offsetInBytes);

@patch
int _loadUint8(Object typedDataBase, int offsetInBytes) =>
    load8(_startOf(typedDataBase) + offsetInBytes);

@patch
int _loadUint16(Object typedDataBase, int offsetInBytes) =>
    load16(_startOf(typedDataBase) + offsetInBytes);

@patch
int _loadUint32(Object typedDataBase, int offsetInBytes) =>
    load32(_startOf(typedDataBase) + offsetInBytes);

@patch
int _loadUint64(Object typedDataBase, int offsetInBytes) =>
    load64(_startOf(typedDataBase) + offsetInBytes);

@patch
double _loadFloat(Object typedDataBase, int offsetInBytes) =>
    loadSingle(_startOf(typedDataBase) + offsetInBytes);

@patch
double _loadDouble(Object typedDataBase, int offsetInBytes) =>
    loadDouble(_startOf(typedDataBase) + offsetInBytes);

@patch
double _loadFloatUnaligned(Object typedDataBase, int offsetInBytes) =>
    loadSingle(_startOf(typedDataBase) + offsetInBytes);

@patch
double _loadDoubleUnaligned(Object typedDataBase, int offsetInBytes) =>
    loadDouble(_startOf(typedDataBase) + offsetInBytes);

@patch
Pointer<S> _loadPointer<S extends NativeType>(
  Object typedDataBase,
  int offsetInBytes,
) => Pointer<Never>._(load64(_startOf(typedDataBase) + offsetInBytes));

@patch
void _storeInt8(Object typedDataBase, int offsetInBytes, int value) =>
    store8(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeInt16(Object typedDataBase, int offsetInBytes, int value) =>
    store16(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeInt32(Object typedDataBase, int offsetInBytes, int value) =>
    store32(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeInt64(Object typedDataBase, int offsetInBytes, int value) =>
    store64(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeUint8(Object typedDataBase, int offsetInBytes, int value) =>
    store8(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeUint16(Object typedDataBase, int offsetInBytes, int value) =>
    store16(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeUint32(Object typedDataBase, int offsetInBytes, int value) =>
    store32(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeUint64(Object typedDataBase, int offsetInBytes, int value) =>
    store64(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeFloat(Object typedDataBase, int offsetInBytes, double value) =>
    storeSingle(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeDouble(Object typedDataBase, int offsetInBytes, double value) =>
    storeDouble(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeFloatUnaligned(
  Object typedDataBase,
  int offsetInBytes,
  double value,
) => storeSingle(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storeDoubleUnaligned(
  Object typedDataBase,
  int offsetInBytes,
  double value,
) => storeDouble(_startOf(typedDataBase) + offsetInBytes, value);

@patch
void _storePointer<S extends NativeType>(
  Object typedDataBase,
  int offsetInBytes,
  Pointer<S> value,
) => store64(_startOf(typedDataBase) + offsetInBytes, value._address);

@patch
void _memCopy(
  Object target,
  int targetOffsetInBytes,
  Object source,
  int sourceOffsetInBytes,
  int lengthInBytes,
) => _copyBytes(
  _startOf(target) + targetOffsetInBytes,
  _startOf(source) + sourceOffsetInBytes,
  lengthInBytes,
);

@patch
Int8List _asExternalTypedDataInt8(Pointer<Int8> ptr, int length) =>
    listAt<Int8List>(0, ptr._address, length);

@patch
Uint8List _asExternalTypedDataUint8(Pointer<Uint8> ptr, int length) =>
    listAt<Uint8List>(1, ptr._address, length);

@patch
Int16List _asExternalTypedDataInt16(Pointer<Int16> ptr, int length) =>
    listAt<Int16List>(2, ptr._address, length);

@patch
Uint16List _asExternalTypedDataUint16(Pointer<Uint16> ptr, int length) =>
    listAt<Uint16List>(3, ptr._address, length);

@patch
Int32List _asExternalTypedDataInt32(Pointer<Int32> ptr, int length) =>
    listAt<Int32List>(4, ptr._address, length);

@patch
Uint32List _asExternalTypedDataUint32(Pointer<Uint32> ptr, int length) =>
    listAt<Uint32List>(5, ptr._address, length);

@patch
Int64List _asExternalTypedDataInt64(Pointer<Int64> ptr, int length) =>
    listAt<Int64List>(6, ptr._address, length);

@patch
Uint64List _asExternalTypedDataUint64(Pointer<Uint64> ptr, int length) =>
    listAt<Uint64List>(7, ptr._address, length);

@patch
Float32List _asExternalTypedDataFloat(Pointer<Float> ptr, int length) =>
    listAt<Float32List>(8, ptr._address, length);

@patch
Float64List _asExternalTypedDataDouble(Pointer<Double> ptr, int length) =>
    listAt<Float64List>(9, ptr._address, length);
