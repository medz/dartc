import 'dart:math';
import 'dart:typed_data';

import 'package:dartc/src/image/fixups.dart';
import 'package:test/test.dart';

/// Follows the chains as the loader does, giving each fixup by its offset.
Map<int, Fixup> _follow(FixedSegment segment, Uint8List table, int pageBytes) {
  final data = ByteData.sublistView(table);
  final bytes = ByteData.sublistView(segment.bytes);
  final starts = data.getUint32(4, .little);
  final info =
      starts + data.getUint32(starts + 4 + segment.number * 4, .little);
  expect(data.getUint16(info + 4, .little), pageBytes);
  expect(data.getUint16(info + 6, .little), 6);
  expect(data.getUint64(info + 8, .little), segment.offset);
  final pages = data.getUint16(info + 20, .little);
  expect(data.getUint32(info, .little), 22 + pages * 2);
  final found = <int, Fixup>{};
  for (var page = 0; page < pages; page++) {
    final first = data.getUint16(info + 22 + page * 2, .little);
    if (first == 0xffff) continue;
    for (var at = page * pageBytes + first; ;) {
      final value = bytes.getUint64(at, .little);
      found[at] = value >>> 63 == 1
          ? Bind(value & 0xffffff)
          : Rebase(value & 0xfffffffff);
      final next = (value >>> 51 & 0xfff) * 4;
      if (next == 0) break;
      at += next;
      expect(at ~/ pageBytes, page, reason: 'a chain stays in its page');
    }
  }
  return found;
}

void main() {
  test('every fixup is found again', () {
    final random = Random(9);
    for (var round = 0; round < 100; round++) {
      final pages = 1 + random.nextInt(4), pageBytes = 0x4000;
      final fixups = <int, Fixup>{
        for (var i = random.nextInt(40); i >= 0; i--)
          random.nextInt(pages * pageBytes ~/ 8) * 8: random.nextBool()
              ? Bind(random.nextInt(5))
              : Rebase(random.nextInt(1 << 32)),
      };
      final segment = FixedSegment(
        number: 2,
        offset: 0x8000,
        bytes: Uint8List(pages * pageBytes),
        fixups: fixups,
      );
      final table = fixupTable(
        [for (var i = 0; i < 5; i++) 'f$i'],
        [segment],
        segments: 5,
        pageBytes: pageBytes,
      );
      segment.link(pageBytes);
      final found = _follow(segment, table, pageBytes);
      expect(found.keys.toSet(), fixups.keys.toSet());
      fixups.forEach((at, fixup) => expect(found[at], fixup));
    }
  });

  test('segments without fixups have no chains', () {
    final table = ByteData.sublistView(
      fixupTable(
        const [],
        [
          FixedSegment(
            number: 1,
            offset: 0,
            bytes: Uint8List(8),
            fixups: {0: Rebase(5)},
          ),
        ],
        segments: 4,
        pageBytes: 16,
      ),
    );
    final starts = table.getUint32(4, .little);
    expect(table.getUint32(starts, .little), 4);
    for (final other in [0, 2, 3]) {
      expect(table.getUint32(starts + 4 + other * 4, .little), 0);
    }
    expect(table.getUint32(starts + 4 + 4, .little), isNot(0));
    expect(table.getUint32(16, .little), 0);
  });

  test('imports are named', () {
    final names = ['labs', 'x', 'toupper'];
    final table = ByteData.sublistView(
      fixupTable(names, const [], segments: 3, pageBytes: 16),
    );
    final imports = table.getUint32(8, .little);
    final symbols = table.getUint32(12, .little);
    expect(table.getUint32(16, .little), 3);
    for (final (i, name) in names.indexed) {
      final import = table.getUint32(imports + i * 4, .little);
      expect(import & 0xff, 1);
      final bytes = table.buffer.asUint8List(
        symbols + (import >> 9),
        name.length + 2,
      );
      expect(String.fromCharCodes(bytes), '_$name\x00');
    }
    expect(table.lengthInBytes % 8, 0);
  });

  test('a page without fixups is skipped', () {
    final segment = FixedSegment(
      number: 0,
      offset: 0,
      bytes: Uint8List(64),
      fixups: {40: Rebase(1)},
    );
    final table = fixupTable(const [], [segment], segments: 1, pageBytes: 16);
    final data = ByteData.sublistView(table);
    final starts = data.getUint32(4, .little);
    final info = starts + data.getUint32(starts + 4, .little);
    expect(
      [for (var i = 0; i < 4; i++) data.getUint16(info + 22 + i * 2, .little)],
      [0xffff, 0xffff, 8, 0xffff],
    );
  });
}
