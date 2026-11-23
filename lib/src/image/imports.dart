import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'relocate.dart';

/// The bytes of one import's stub.
const stubBytes = 12;

/// Code jumping through each import's slot.
///
/// Stub i is at [address] plus i times [stubBytes], and uses the 8-byte slot
/// i at [slots]. It changes only x16, which calls never preserve.
Uint8List importStubs(List<String> names, int address, int slots) {
  final out = ByteWriter(.little);
  for (final (i, name) in names.indexed) {
    final at = address + i * stubBytes, slot = slots + i * 8;
    out
      ..u32(0x90000010 | pageField(at, slot, name)) // adrp x16
      ..u32(0xf9400210 | ((slot & 0xfff) >> 3) << 10) // ldr x16, [x16, ..]
      ..u32(0xd61f0200); // br x16
  }
  return out.finish();
}

/// The unbound slots, each naming its import and linking to the next slot.
///
/// The loader follows one chain per page of [pageBytes].
Uint8List importSlots(int count, int pageBytes) {
  final out = ByteWriter(.little);
  for (var i = 0; i < count; i++) {
    final last = i + 1 == count || (i + 1) * 8 % pageBytes == 0;
    // Distances between slots are in units of four bytes.
    out.u64(1 << 63 | (last ? 0 : 2) << 51 | i);
  }
  return out.finish();
}

/// Tells the loader where the slots are and which symbols they bind.
///
/// The slots fill segment number [segment], [segmentOffset] bytes after the
/// start of the image. Every name comes from the first loaded library.
Uint8List importTable(
  List<String> names, {
  required int segments,
  required int segment,
  required int segmentOffset,
  required int pageBytes,
}) {
  const header = 28, startsHeader = 22;
  final pages = (names.length * 8 + pageBytes - 1) ~/ pageBytes;
  final startsOffset = (header + 7) & ~7;
  final segmentStarts = (4 + segments * 4 + 7) & ~7;
  final startsBytes = startsHeader + pages * 2;
  final imports = (startsOffset + segmentStarts + startsBytes + 3) & ~3;
  final symbols = imports + names.length * 4;
  final out = ByteWriter(.little)
    ..u32(0) // Version.
    ..u32(startsOffset)
    ..u32(imports)
    ..u32(symbols)
    ..u32(names.length)
    ..u32(1) // Plain imports.
    ..u32(0) // Uncompressed names.
    ..align(8)
    ..u32(segments);
  for (var i = 0; i < segments; i++) {
    out.u32(i == segment ? segmentStarts : 0);
  }
  out
    ..align(8)
    ..u32(startsBytes)
    ..u16(pageBytes)
    ..u16(6) // 64-bit pointers holding image offsets.
    ..u64(segmentOffset)
    ..u32(0) // No limit on plain values.
    ..u16(pages);
  for (var i = 0; i < pages; i++) {
    out.u16(0); // Each page's chain starts at its first slot.
  }
  out.align(4);
  var name = 1;
  for (final text in names) {
    out.u32(1 | name << 9);
    name += utf8.encode(text).length + 2;
  }
  out.u8(0);
  for (final text in names) {
    out.text('_$text', utf8.encode(text).length + 2);
  }
  out.align(8);
  return out.finish();
}
