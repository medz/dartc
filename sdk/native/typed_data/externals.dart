// Lists that are somewhere in memory.
import 'dart:_heap/machine.dart'
    show
        load8,
        load32,
        load32Signed,
        load64,
        store8,
        store32,
        store64;
import 'dart:_heap/objects.dart'
    show
        load16,
        loadDouble,
        loadSingle,
        store16,
        storeDouble,
        storeSingle;

/// Where the bytes of [data] are.
int _dataAddress(Object data) {
  if (data is _TypedListBase) {
    return data._typedData._start + data.offsetInBytes;
  }
  final view = unsafeCast<_ByteDataView>(data);
  return view._typedData._start + view.offsetInBytes;
}

/// A list of [length] elements, of a kind, at [address].
Object _listAt(int kind, int address, int length) => switch (kind) {
  0 => _ExternalInt8Array._(address, length),
  1 => _ExternalUint8Array._(address, length),
  2 => _ExternalInt16Array._(address, length),
  3 => _ExternalUint16Array._(address, length),
  4 => _ExternalInt32Array._(address, length),
  5 => _ExternalUint32Array._(address, length),
  6 => _ExternalInt64Array._(address, length),
  7 => _ExternalUint64Array._(address, length),
  8 => _ExternalFloat32Array._(address, length),
  _ => _ExternalFloat64Array._(address, length),
};

@patch
class _ExternalInt8Array {
  final int _address;
  final int length;
  _ExternalInt8Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getInt8(index);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalUint8Array {
  final int _address;
  final int length;
  _ExternalUint8Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getUint8(index);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalInt16Array {
  final int _address;
  final int length;
  _ExternalInt16Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getInt16(index << 1);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalUint16Array {
  final int _address;
  final int length;
  _ExternalUint16Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getUint16(index << 1);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalInt32Array {
  final int _address;
  final int length;
  _ExternalInt32Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getInt32(index << 2);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalUint32Array {
  final int _address;
  final int length;
  _ExternalUint32Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getUint32(index << 2);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalInt64Array {
  final int _address;
  final int length;
  _ExternalInt64Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getInt64(index << 3);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalUint64Array {
  final int _address;
  final int length;
  _ExternalUint64Array._(this._address, this.length);

  int get _start => _address;

  @patch
  int operator [](int index) {
    _checkRead(index, length);
    return _getUint64(index << 3);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalFloat32Array {
  final int _address;
  final int length;
  _ExternalFloat32Array._(this._address, this.length);

  int get _start => _address;

  @patch
  double operator [](int index) {
    _checkRead(index, length);
    return _getFloat32(index << 2);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}

@patch
class _ExternalFloat64Array {
  final int _address;
  final int length;
  _ExternalFloat64Array._(this._address, this.length);

  int get _start => _address;

  @patch
  double operator [](int index) {
    _checkRead(index, length);
    return _getFloat64(index << 3);
  }
  int _getInt8(int offsetInBytes) => (load8(_address + offsetInBytes) ^ 0x80) - 0x80;
  void _setInt8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getUint8(int offsetInBytes) => load8(_address + offsetInBytes);
  void _setUint8(int offsetInBytes, int value) =>
      store8(_address + offsetInBytes, value);
  int _getInt16(int offsetInBytes) => (load16(_address + offsetInBytes) ^ 0x8000) - 0x8000;
  void _setInt16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getUint16(int offsetInBytes) => load16(_address + offsetInBytes);
  void _setUint16(int offsetInBytes, int value) =>
      store16(_address + offsetInBytes, value);
  int _getInt32(int offsetInBytes) => load32Signed(_address + offsetInBytes);
  void _setInt32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getUint32(int offsetInBytes) => load32(_address + offsetInBytes);
  void _setUint32(int offsetInBytes, int value) =>
      store32(_address + offsetInBytes, value);
  int _getInt64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setInt64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  int _getUint64(int offsetInBytes) => load64(_address + offsetInBytes);
  void _setUint64(int offsetInBytes, int value) =>
      store64(_address + offsetInBytes, value);
  double _getFloat32(int offsetInBytes) => loadSingle(_address + offsetInBytes);
  void _setFloat32(int offsetInBytes, double value) =>
      storeSingle(_address + offsetInBytes, value);
  double _getFloat64(int offsetInBytes) => loadDouble(_address + offsetInBytes);
  void _setFloat64(int offsetInBytes, double value) =>
      storeDouble(_address + offsetInBytes, value);
}
