import 'dart:typed_data';

import 'package:dartc/lir.dart';

import 'code.dart';

/// The stack words holding references while a call is made.
///
/// [returnOffset] is where the call returns to, from the start of the code;
/// [offsets] are from the caller's frame address.
final class StackMap(final int returnOffset, Iterable<int> offsets) {
  final List<int> offsets = .unmodifiable(offsets);
}

/// Where the call returning to [returnOffset] continues if it throws.
///
/// The code at [target] finds its frame's address, the exception and the trace
/// in registers. Offsets are from the start of the code.
final class const ThrowTarget(final int returnOffset, final int target);

/// Encodes [targets], which are sorted, for the runtime to search: their count
/// and the two offsets of each, as 32-bit words.
Uint8List encodeThrowTargets(List<ThrowTarget> targets) {
  final data = ByteData((1 + targets.length * 2) * 4)
    ..setInt32(0, targets.length, .little);
  for (final (i, ThrowTarget(:returnOffset, :target)) in targets.indexed) {
    data
      ..setInt32(4 + i * 8, returnOffset, .little)
      ..setInt32(8 + i * 8, target, .little);
  }
  return data.buffer.asUint8List();
}

/// Encodes [maps], which are sorted, for the runtime to search.
///
/// All words have 32 bits. The number of pages of the code, of 4096 bytes each,
/// is followed by the number of the first map for each page and for the end.
/// Then comes a word for each map: 12 bits for where its call returns to in the
/// page, and 20 for the word where its record is in what follows.
///
/// A record is a count and that many offsets of 8 bytes, in 16 bits each, the
/// lower half of a word first. If one does not fit, the highest bit of the count
/// is set, and the offsets have a word each, after that of the count.
Uint8List encodeStackMaps(List<StackMap> maps) {
  final pages = maps.isEmpty ? 0 : (maps.last.returnOffset >> 12) + 1;
  final starts = <int>[], index = <int>[], records = <int>[];
  final places = <String, int>{};
  for (final StackMap(:returnOffset, :offsets) in maps) {
    while (starts.length <= returnOffset >> 12) {
      starts.add(index.length);
    }
    final at = places.putIfAbsent('$offsets', () {
      final at = records.length;
      records.addAll(_recordOf(offsets));
      return at;
    });
    if (at >= 1 << 20) throw EmitUnsupported(stackMapSymbol, 'so many calls');
    index.add((returnOffset & 0xfff) << 20 | at);
  }
  starts.add(index.length);
  final words = [pages, ...starts, ...index, ...records];
  final data = ByteData(words.length * 4);
  for (final (i, word) in words.indexed) {
    data.setUint32(i * 4, word & 0xffffffff, .little);
  }
  return data.buffer.asUint8List();
}

List<int> _recordOf(List<int> offsets) {
  final words = [for (final offset in offsets) offset ~/ 8];
  final isShort = words.every((word) => word >= -0x8000 && word < 0x8000);
  if (!isShort) return [0x8000 | words.length, ...words];
  final halves = [words.length, ...words, 0];
  return [
    for (var i = 0; i + 1 < halves.length; i += 2)
      (halves[i + 1] & 0xffff) << 16 | halves[i] & 0xffff,
  ];
}
