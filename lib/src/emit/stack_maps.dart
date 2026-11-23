import 'dart:typed_data';

/// The stack words holding references while a call is made.
///
/// [returnOffset] is where the call returns to, from the start of the code;
/// [offsets] are from the caller's frame address.
final class StackMap(final int returnOffset, Iterable<int> offsets) {
  final List<int> offsets = .unmodifiable(offsets);
}

/// Encodes [maps], which are sorted, for the runtime to search.
///
/// The count is followed by two words for each map: where its call returns to,
/// and where its record is in these bytes. A record is a count and that many
/// offsets. All words have 32 bits.
Uint8List encodeStackMaps(List<StackMap> maps) {
  final records = <String, int>{}, words = <int>[];
  final start = 1 + maps.length * 2;
  final index = [
    for (final map in maps) ...[
      map.returnOffset,
      records.putIfAbsent('${map.offsets}', () {
        final at = (start + words.length) * 4;
        words
          ..add(map.offsets.length)
          ..addAll(map.offsets);
        return at;
      }),
    ],
  ];
  final data = ByteData((start + words.length) * 4);
  for (final (i, word) in [maps.length, ...index, ...words].indexed) {
    data.setInt32(i * 4, word, .little);
  }
  return data.buffer.asUint8List();
}
