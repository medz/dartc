import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/lir.dart';

/// Encodes where calls are in the source, for the runtime to search by where
/// they return to.
///
/// All words have 32 bits. The number of calls is followed by two words for
/// each, sorted: where it returns to, and its place plus one. The number of
/// places follows, then four words for each: where the texts of its function
/// and of its file are, its line, and the place plus one that it is in, or 0.
/// The texts come last, each a word for its length in bytes and its UTF-8.
Uint8List encodePlaces(List<(int, LirPlace)> calls) {
  final records = <int>[], numbers = Map<LirPlace, int>.identity();
  final texts = BytesBuilder(), textPlaces = <String, int>{};
  int text(String value) => textPlaces.putIfAbsent(value, () {
    final at = texts.length, bytes = utf8.encode(value);
    texts
      ..add((ByteData(4)..setUint32(0, bytes.length, .little)).buffer
          .asUint8List())
      ..add(bytes);
    return at;
  });
  int number(LirPlace place) {
    if (numbers[place] case final found?) return found;
    final outer = place.outer == null ? 0 : number(place.outer!) + 1;
    final at = records.length ~/ 4;
    records.addAll([text(place.function), text(place.uri), place.line, outer]);
    return numbers[place] = at;
  }

  final sorted = [...calls]..sort((a, b) => a.$1.compareTo(b.$1));
  final words = [
    sorted.length,
    for (final (offset, place) in sorted) ...[offset, number(place) + 1],
    records.length ~/ 4,
    ...records,
  ];
  final data = ByteData(words.length * 4);
  for (final (i, word) in words.indexed) {
    data.setUint32(i * 4, word, .little);
  }
  return (BytesBuilder()
        ..add(data.buffer.asUint8List())
        ..add(texts.takeBytes()))
      .takeBytes();
}
