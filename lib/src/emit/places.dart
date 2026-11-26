import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/lir.dart';

import 'unsupported.dart';

/// Encodes where calls are in the source, for the runtime to search by where
/// they return to.
///
/// All words have 32 bits. As for stack maps, the number of pages of the code,
/// of 4096 bytes each, is followed by the number of the first call for each
/// page and for the end, then a word for each call: 12 bits for where it
/// returns to in the page, and 20 for its place. The number of places follows,
/// then three words for each: where the text of its function is, the number of
/// its file shifted by 20 bits with its line, and the place plus one that it is
/// in, or 0. Then come the number of files and where the text of each is. The
/// texts come last, each a word for its length in bytes and its UTF-8.
Uint8List encodePlaces(List<(int, LirPlace)> calls) {
  final records = <int>[], numbers = Map<LirPlace, int>.identity();
  final known = <(int, int, int, int), int>{}, files = <String, int>{};
  final texts = BytesBuilder(), textPlaces = <String, int>{};
  int text(String value) => textPlaces.putIfAbsent(value, () {
    final at = texts.length, bytes = utf8.encode(value);
    texts
      ..add(
        (ByteData(4)..setUint32(0, bytes.length, .little)).buffer.asUint8List(),
      )
      ..add(bytes);
    return at;
  });
  int number(LirPlace place) {
    if (numbers[place] case final found?) return found;
    final outer = place.outer == null ? 0 : number(place.outer!) + 1;
    final file = files.putIfAbsent(place.uri, () => files.length);
    if (file >= 1 << 12 || place.line >= 1 << 20) {
      throw EmitUnsupported(placesSymbol, 'so many files or lines');
    }
    final key = (text(place.function), file, place.line, outer);
    return numbers[place] = known.putIfAbsent(key, () {
      records.addAll([key.$1, file << 20 | place.line, outer]);
      return records.length ~/ 3 - 1;
    });
  }

  final sorted = [...calls]..sort((a, b) => a.$1.compareTo(b.$1));
  final starts = <int>[], entries = <int>[];
  for (final (offset, place) in sorted) {
    while (starts.length <= offset >> 12) {
      starts.add(entries.length);
    }
    final at = number(place);
    if (at >= 1 << 20) throw EmitUnsupported(placesSymbol, 'so many places');
    entries.add((offset & 0xfff) << 20 | at);
  }
  starts.add(entries.length);
  final words = [
    starts.length - 1,
    ...starts,
    ...entries,
    records.length ~/ 3,
    ...records,
    files.length,
    for (final file in files.keys) text(file),
  ];
  final data = ByteData(words.length * 4);
  for (final (i, word) in words.indexed) {
    data.setUint32(i * 4, word & 0xffffffff, .little);
  }
  return (BytesBuilder()
        ..add(data.buffer.asUint8List())
        ..add(texts.takeBytes()))
      .takeBytes();
}
