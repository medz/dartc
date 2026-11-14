import 'dart:ffi';

import 'memory.dart';

/// Writes a UTF-8 line, replacing unpaired UTF-16 surrogates with U+FFFD.
void writeLine(String line) {
  final capacity = line.length * 4 + 1;
  final buffer = Memory.map(capacity);
  if (buffer == 0) Memory.fail();
  try {
    var length = 0;
    void byte(int value) {
      Pointer<Uint8>.fromAddress(buffer + length++).value = value;
    }

    for (var i = 0; i < line.length; i++) {
      var rune = line.codeUnitAt(i);
      if (rune >= 0xd800 && rune <= 0xdbff && i + 1 < line.length) {
        final low = line.codeUnitAt(i + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          rune = 0x10000 + ((rune - 0xd800) << 10) + low - 0xdc00;
          i++;
        }
      }
      if (rune >= 0xd800 && rune <= 0xdfff) rune = 0xfffd;
      if (rune < 0x80) {
        byte(rune);
      } else {
        if (rune >= 0x10000) {
          byte(0xf0 | (rune >> 18));
          byte(0x80 | ((rune >> 12) & 63));
        } else if (rune >= 0x800) {
          byte(0xe0 | (rune >> 12));
        } else {
          byte(0xc0 | (rune >> 6));
        }
        if (rune >= 0x800) byte(0x80 | ((rune >> 6) & 63));
        byte(0x80 | (rune & 63));
      }
    }
    byte(10);
    var written = 0;
    while (written < length) {
      final count = Memory.writeBytes(1, buffer + written, length - written);
      if (count == -4) continue;
      if (count <= 0) throw StateError('Console write failed');
      written += count;
    }
  } finally {
    Memory.unmap(buffer, capacity);
  }
}
