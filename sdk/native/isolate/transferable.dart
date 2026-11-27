// Bytes that move to another isolate without being copied again.
import 'dart:_heap/objects.dart' show dataAddress;
import 'dart:ffi' show Int64, Native, Void;

@Native<Void Function(Int64, Int64, Int64)>(symbol: 'memcpy')
external void _copyBytes(int to, int from, int count);

@patch
abstract final class TransferableTypedData {
  @patch
  factory TransferableTypedData.fromList(List<TypedData> list) {
    var length = 0;
    for (final data in list) {
      length += data.lengthInBytes;
    }
    final address = _allocate(length == 0 ? 1 : length);
    if (address == 0) throw OutOfMemoryError();
    var at = address;
    for (final data in list) {
      _copyBytes(at, dataAddress(data), data.lengthInBytes);
      at += data.lengthInBytes;
    }
    return _TransferableTypedDataImpl(address, length);
  }
}

/// Bytes in memory of C, which belong to whatever isolate has this object
/// until they are materialized or sent.
final class _TransferableTypedDataImpl implements TransferableTypedData {
  final int _address, _length;
  bool _isGone = false;

  _TransferableTypedDataImpl(this._address, this._length);

  ByteBuffer materialize() {
    if (_isGone) {
      throw ArgumentError(
        'Attempt to materialize object that was transferred already.',
      );
    }
    _isGone = true;
    final bytes = Uint8List(_length);
    _copyBytes(dataAddress(bytes), _address, _length);
    _free(_address);
    return bytes.buffer;
  }
}
