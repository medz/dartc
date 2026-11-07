import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';

/// Writes ELF64 relocatable objects for Linux ARM64 and x86-64.
abstract final class Elf() {
  /// Encodes the code section, symbol tables and a non-executable stack note.
  static Uint8List encode(ObjectFile object) {
    if (object.target.operatingSystem != .linux) {
      throw ArgumentError('ELF output requires a Linux target.');
    }
    final strings = <int>[0], names = <int>[];
    for (final symbol in object.symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    final sectionNames = utf8.encode(
      '\u0000.text\u0000.symtab\u0000.strtab\u0000.shstrtab\u0000.note.GNU-stack\u0000',
    );
    const textOffset = 64;
    final symbolOffset = (textOffset + object.code.length + 7) & ~7;
    final symbolSize = (object.symbols.length + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final nameOffset = stringOffset + strings.length;
    final sectionOffset = (nameOffset + sectionNames.length + 7) & ~7;
    final data = ByteData(sectionOffset + 6 * 64);
    final bytes = data.buffer.asUint8List();
    bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
    data.setUint16(16, 1, .little);
    data.setUint16(
      18,
      object.target.architecture == .arm64 ? 183 : 62,
      .little,
    );
    data.setUint32(20, 1, .little);
    data.setUint64(40, sectionOffset, .little);
    data.setUint16(52, 64, .little);
    data.setUint16(58, 64, .little);
    data.setUint16(60, 6, .little);
    data.setUint16(62, 4, .little);
    bytes.setAll(textOffset, object.code);
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, sectionNames);
    for (final (i, symbol) in object.symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, 0x12);
      data.setUint16(offset + 6, 1, .little);
      data.setUint64(offset + 8, symbol.offset, .little);
      data.setUint64(offset + 16, symbol.size, .little);
    }
    void section(
      int index,
      int name,
      int type,
      int flags,
      int offset,
      int size, {
      int link = 0,
      int info = 0,
      int alignment = 1,
      int entrySize = 0,
    }) {
      final base = sectionOffset + index * 64;
      data.setUint32(base, name, .little);
      data.setUint32(base + 4, type, .little);
      data.setUint64(base + 8, flags, .little);
      data.setUint64(base + 24, offset, .little);
      data.setUint64(base + 32, size, .little);
      data.setUint32(base + 40, link, .little);
      data.setUint32(base + 44, info, .little);
      data.setUint64(base + 48, alignment, .little);
      data.setUint64(base + 56, entrySize, .little);
    }

    section(1, 1, 1, 6, textOffset, object.code.length, alignment: 16);
    section(
      2,
      7,
      2,
      0,
      symbolOffset,
      symbolSize,
      link: 3,
      info: 1,
      alignment: 8,
      entrySize: 24,
    );
    section(3, 15, 3, 0, stringOffset, strings.length);
    section(4, 23, 3, 0, nameOffset, sectionNames.length);
    section(5, 33, 1, 0, 0, 0);
    return bytes;
  }
}
