import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';

import '../object_module.dart';
import '../object_format.dart';
import 'records.dart';

/// Writes ELF64 relocatable objects for Linux ARM64 and x86-64.
final class Elf(@override final Target target) implements ObjectFormat {
  this {
    if (target.operatingSystem != .linux) {
      throw ArgumentError('ELF requires a Linux target.');
    }
  }

  @override
  Uint8List encodeObject(ObjectModule object) {
    if (object.target != target) throw ArgumentError('ELF target mismatch.');
    const textOffset = 64;
    final order = [for (var i = 0; i < object.symbols.length; i++) i]
      ..sort(
        (a, b) => object.symbols[a].binding.index.compareTo(
          object.symbols[b].binding.index,
        ),
      );
    final symbols = [for (final i in order) object.symbols[i]];
    final indices = {
      for (final (i, original) in order.indexed) original: i + 1,
    };
    final imports = object.imports;
    final count = symbols.length + imports.length;
    final strings = <int>[0], names = <int>[];
    for (final name in [...symbols.map((s) => s.name), ...imports]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final sectionNames =
        '\u0000.text\u0000.symtab\u0000.strtab\u0000.shstrtab\u0000.note.GNU-stack\u0000.rela.text\u0000';
    final relocations = object.relocations;
    final relocationOffset = (textOffset + object.code.length + 7) & ~7;
    final symbolOffset = relocationOffset + relocations.length * 24;
    final symbolSize = (count + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final nameOffset = stringOffset + strings.length;
    final sectionOffset = (nameOffset + sectionNames.length + 7) & ~7;
    final sectionCount = relocations.isNotEmpty ? 7 : 6;
    final data = ByteData(sectionOffset + sectionCount * 64);
    final bytes = data.buffer.asUint8List();
    data.writeElf64Header(
      architecture: object.target.architecture,
      type: 1,
      sectionOffset: sectionOffset,
      sectionCount: sectionCount,
      sectionNames: 4,
    );
    bytes.setAll(textOffset, object.code);
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, ascii.encode(sectionNames));
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, symbol.binding == .local ? 0x02 : 0x12);
      data.setUint8(
        offset + 5,
        symbol.binding == .global && !symbol.exported ? 2 : 0,
      );
      data.setUint16(offset + 6, 1, .little);
      data.setUint64(offset + 8, symbol.offset, .little);
      data.setUint64(offset + 16, symbol.size, .little);
    }
    for (final (i, _) in imports.indexed) {
      final offset = symbolOffset + (symbols.length + i + 1) * 24;
      data.setUint32(offset, names[symbols.length + i], .little);
      data.setUint8(offset + 4, 0x12);
    }
    for (final (i, relocation) in relocations.indexed) {
      final index = relocation.symbol < object.symbols.length
          ? indices[relocation.symbol]!
          : symbols.length + 1 + relocation.symbol - object.symbols.length;
      final offset = relocationOffset + i * 24;
      final arm = relocation.encoding == .arm64Call26;
      data.setUint64(offset, relocation.offset, .little);
      data.setUint64(
        offset + 8,
        index << 32 |
            (arm
                ? 283
                : relocation.symbol < object.symbols.length &&
                      object.symbols[relocation.symbol].binding == .local
                ? 2
                : 4),
        .little,
      );
      data.setInt64(offset + 16, arm ? 0 : -4, .little);
    }
    void section(
      int index,
      String name,
      int type,
      int flags,
      int offset,
      int size, {
      int link = 0,
      int info = 0,
      int alignment = 1,
      int entrySize = 0,
    }) {
      data.writeElf64Section(
        sectionOffset + index * 64,
        name: sectionNames.indexOf('$name\u0000'),
        type: type,
        flags: flags,
        fileOffset: offset,
        size: size,
        link: link,
        info: info,
        alignment: alignment,
        entrySize: entrySize,
      );
    }

    section(1, '.text', 1, 6, textOffset, object.code.length, alignment: 16);
    section(
      2,
      '.symtab',
      2,
      0,
      symbolOffset,
      symbolSize,
      link: 3,
      info: 1 + symbols.where((s) => s.binding == .local).length,
      alignment: 8,
      entrySize: 24,
    );
    section(3, '.strtab', 3, 0, stringOffset, strings.length);
    section(4, '.shstrtab', 3, 0, nameOffset, sectionNames.length);
    if (relocations.isNotEmpty) {
      section(
        6,
        '.rela.text',
        4,
        0,
        relocationOffset,
        relocations.length * 24,
        link: 2,
        info: 1,
        alignment: 8,
        entrySize: 24,
      );
    }
    section(5, '.note.GNU-stack', 1, 0, 0, 0);
    return bytes.asUnmodifiableView();
  }
}
