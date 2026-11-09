import 'dart:typed_data';

import 'package:dartc/object/elf.dart';
import 'package:test/test.dart';

void main() {
  test('ELF records respect buffer views and initialize reserved bytes', () {
    final bytes = Uint8List(144)..fillRange(0, 144, 0xff);
    final data = ByteData.sublistView(bytes, 8, 136);
    data.writeElf64Header(
      architecture: .arm64,
      type: 3,
      sectionOffset: 64,
      sectionCount: 1,
      sectionNames: 0,
      programCount: 3,
    );
    expect(bytes.sublist(8, 15), [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
    expect(bytes.sublist(15, 24), everyElement(0));
    expect(data.getUint64(24, .little), 0);
    expect(data.getUint16(18, .little), 183);
    expect(data.getUint64(32, .little), 64);
    expect(data.getUint16(56, .little), 3);
    data.writeElf64Section(
      64,
      name: 1,
      type: 1,
      flags: 6,
      fileOffset: 240,
      size: 4,
      address: 240,
      alignment: 16,
    );
    expect(data.getUint64(80, .little), 240);
    expect(data.getUint64(88, .little), 240);
    expect(data.getUint64(96, .little), 4);
    expect(data.getUint32(104, .little), 0);
    expect(data.getUint32(108, .little), 0);
    expect(data.getUint64(112, .little), 16);
    expect(data.getUint64(120, .little), 0);
    expect([...bytes.take(8), ...bytes.skip(136)], everyElement(0xff));
  });

  test('invalid ELF record fields fail before changing the buffer', () {
    final bytes = Uint8List(64)..fillRange(0, 64, 0xff);
    final data = ByteData.sublistView(bytes);
    for (final count in [-1, 0x10000]) {
      expect(
        () => data.writeElf64Header(
          architecture: .x64,
          type: 1,
          sectionOffset: 64,
          sectionCount: count,
          sectionNames: 0,
        ),
        throwsRangeError,
      );
    }
    for (final (offset, name, size) in [
      (1, 0, 0),
      (0, 1 << 32, 0),
      (0, 0, -1),
    ]) {
      expect(
        () => data.writeElf64Section(
          offset,
          name: name,
          type: 1,
          flags: 0,
          fileOffset: 0,
          size: size,
        ),
        throwsRangeError,
      );
    }
    expect(bytes, everyElement(0xff));
  });
}
