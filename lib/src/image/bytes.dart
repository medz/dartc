import 'dart:convert';
import 'dart:typed_data';

/// A growing byte sequence with fixed-width integers.
final class ByteWriter(final Endian endian) {
  final _bytes = BytesBuilder(copy: false);

  int get length => _bytes.length;

  void _word(int size, void Function(ByteData data) write) {
    final data = ByteData(size);
    write(data);
    _bytes.add(data.buffer.asUint8List());
  }

  void u8(int value) => _word(1, (data) => data.setUint8(0, value));
  void u32(int value) => _word(4, (data) => data.setUint32(0, value, endian));
  void u64(int value) => _word(8, (data) => data.setUint64(0, value, endian));

  void bytes(List<int> values) => _bytes.add(Uint8List.fromList(values));

  /// Writes [value] followed by zeros, filling exactly [size] bytes.
  void text(String value, int size) {
    final encoded = utf8.encode(value);
    if (encoded.length > size) throw ArgumentError.value(value, 'value');
    bytes(encoded);
    zeros(size - encoded.length);
  }

  void zeros(int count) => bytes(Uint8List(count));

  /// Adds zeros up to the next multiple of [alignment].
  void align(int alignment) => zeros(-length % alignment);

  Uint8List finish() => _bytes.toBytes();
}
