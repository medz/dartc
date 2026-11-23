import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// A word that the loader fills in when the program starts.
sealed class const Fixup() {
  /// The bits other than the distance to the next fixup.
  int get _bits;
}

/// The address of an import, by its number.
final class const Bind(final int import) extends Fixup {
  @override
  int get _bits => 1 << 63 | import;
  @override
  bool operator ==(Object other) => other is Bind && other.import == import;
  @override
  int get hashCode => import;
}

/// An address inside the image, by its distance from the start.
final class const Rebase(final int offset) extends Fixup {
  @override
  int get _bits => offset;
  @override
  bool operator ==(Object other) => other is Rebase && other.offset == offset;
  @override
  int get hashCode => offset;
}

/// Segment [number] of the image, starting [offset] bytes after it, with the
/// words of [bytes] to fill in.
final class FixedSegment({
  required final int number,
  required final int offset,
  required final Uint8List bytes,
  required final Map<int, Fixup> fixups,
}) {
  late final List<int> _positions = fixups.keys.toList()..sort();

  /// Writes the fixups, each leading to the next in its page.
  void link(int pageBytes) {
    final words = ByteData.sublistView(bytes);
    for (final (i, at) in _positions.indexed) {
      final next = _positions.elementAtOrNull(i + 1);
      final isLast = next == null || next ~/ pageBytes != at ~/ pageBytes;
      // Distances are in units of four bytes.
      final distance = isLast ? 0 : (next - at) ~/ 4;
      words.setUint64(at, fixups[at]!._bits | distance << 51, .little);
    }
  }

  /// Where each page's first fixup is, or 0xffff for none.
  List<int> _starts(int pageBytes) => [
    for (var page = 0; page * pageBytes < bytes.length; page++)
      _positions
              .where((at) => at ~/ pageBytes == page)
              .map((at) => at % pageBytes)
              .firstOrNull ??
          0xffff,
  ];
}

/// Tells the loader where the fixups of [fixed] are and what [imports] name.
///
/// Every import comes from the first loaded library. [segments] counts those
/// without fixups too.
Uint8List fixupTable(
  List<String> imports,
  List<FixedSegment> fixed, {
  required int segments,
  required int pageBytes,
}) {
  const header = 28, startsHeader = 22;
  final startsOffset = (header + 7) & ~7;
  final infos = [
    for (final segment in fixed) _segmentInfo(segment, pageBytes, startsHeader),
  ];
  final infoOffsets = List.filled(segments, 0);
  var end = (4 + segments * 4 + 7) & ~7;
  for (final (i, info) in infos.indexed) {
    infoOffsets[fixed[i].number] = end;
    end += info.length;
  }
  final importsOffset = startsOffset + end;
  final symbols = importsOffset + imports.length * 4;
  final out = ByteWriter(.little)
    ..u32(0) // Version.
    ..u32(startsOffset)
    ..u32(importsOffset)
    ..u32(symbols)
    ..u32(imports.length)
    ..u32(1) // Plain imports.
    ..u32(0) // Uncompressed names.
    ..align(8)
    ..u32(segments);
  infoOffsets.forEach(out.u32);
  out.align(8);
  infos.forEach(out.bytes);
  var name = 1;
  for (final text in imports) {
    out.u32(1 | name << 9);
    name += utf8.encode(text).length + 2;
  }
  out.u8(0);
  for (final text in imports) {
    out.text('_$text', utf8.encode(text).length + 2);
  }
  out.align(8);
  return out.finish();
}

Uint8List _segmentInfo(FixedSegment segment, int pageBytes, int header) {
  final starts = segment._starts(pageBytes);
  final out = ByteWriter(.little)
    ..u32(header + starts.length * 2)
    ..u16(pageBytes)
    ..u16(6) // 64-bit pointers holding image offsets.
    ..u64(segment.offset)
    ..u32(0) // No limit on plain values.
    ..u16(starts.length);
  starts.forEach(out.u16);
  out.align(8);
  return out.finish();
}
