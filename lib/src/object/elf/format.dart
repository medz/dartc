import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';

import '../object_module.dart';
import '../object_format.dart';
import 'records.dart';
import 'reader.dart';

/// Reads and writes ELF64 relocatable objects for Linux ARM64 and x86-64.
final class Elf(@override final Target target) implements ObjectFormat {
  this {
    if (target.operatingSystem != .linux) {
      throw ArgumentError('ELF requires a Linux target.');
    }
  }

  @override
  ObjectModule decodeObject(Uint8List bytes) => ElfReader(target, bytes).read();

  @override
  Uint8List encodeObject(ObjectModule object) {
    if (object.target != target) throw ArgumentError('ELF target mismatch.');
    final sections = object.sections, relocations = object.relocations;
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
    final count = symbols.length + object.imports.length;
    final strings = <int>[0], names = <int>[];
    for (final name in [...symbols.map((s) => s.name), ...object.imports]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final offsets = <int>[], relocationOffsets = <int>[];
    final groups = [
      for (var i = 0; i < sections.length; i++)
        relocations.where((r) => r.section == i).toList(),
    ];
    var cursor = 64;
    for (final section in sections) {
      cursor = (cursor + section.alignment - 1) & -section.alignment;
      offsets.add(cursor);
      cursor += section.bytes.length;
    }
    cursor = (cursor + 7) & ~7;
    for (final group in groups) {
      relocationOffsets.add(cursor);
      cursor += group.length * 24;
    }
    final symbolIndex = sections.length + 1, stringIndex = symbolIndex + 1;
    final nameIndex = symbolIndex + 2, stackIndex = symbolIndex + 3;
    final symbolOffset = cursor, symbolSize = (count + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final nameOffset = stringOffset + strings.length;
    final sectionNames = [
      '',
      for (final section in sections) section.kind.elfName,
      '.symtab',
      '.strtab',
      '.shstrtab',
      '.note.GNU-stack',
      for (final (i, group) in groups.indexed)
        if (group.isNotEmpty) '.rela${sections[i].kind.elfName}',
    ];
    if (sectionNames.length >= 0xff00) {
      throw UnsupportedError('ELF requires extended section indices.');
    }
    final nameBytes = <int>[], nameOffsets = <int>[];
    for (final name in sectionNames) {
      nameOffsets.add(nameBytes.length);
      nameBytes.addAll([...ascii.encode(name), 0]);
    }
    final sectionOffset = (nameOffset + nameBytes.length + 7) & ~7;
    final data = ByteData(sectionOffset + sectionNames.length * 64);
    final bytes = data.buffer.asUint8List();
    data.writeElf64Header(
      architecture: target.architecture,
      type: 1,
      sectionOffset: sectionOffset,
      sectionCount: sectionNames.length,
      sectionNames: nameIndex,
    );
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, nameBytes);
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(
        offset + 4,
        (symbol.binding == .local ? 0 : 0x10) | symbol.kind.elfType,
      );
      data.setUint8(
        offset + 5,
        symbol.binding == .global && !symbol.exported ? 2 : 0,
      );
      data.setUint16(offset + 6, symbol.section + 1, .little);
      data.setUint64(offset + 8, symbol.offset, .little);
      data.setUint64(offset + 16, symbol.size ?? 0, .little);
    }
    for (final (i, _) in object.imports.indexed) {
      final offset = symbolOffset + (symbols.length + i + 1) * 24;
      data.setUint32(offset, names[symbols.length + i], .little);
      data.setUint8(offset + 4, 0x10);
    }
    void section(
      int index,
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
        name: nameOffsets[index],
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

    var relocationIndex = stackIndex + 1;
    for (final (i, input) in sections.indexed) {
      bytes.setAll(offsets[i], input.bytes);
      section(
        i + 1,
        input.kind.elfType,
        input.kind.elfFlags,
        offsets[i],
        input.size,
        alignment: input.alignment,
      );
      final group = groups[i];
      if (group.isEmpty) continue;
      section(
        relocationIndex++,
        4,
        0,
        relocationOffsets[i],
        group.length * 24,
        link: symbolIndex,
        info: i + 1,
        alignment: 8,
        entrySize: 24,
      );
      for (final (j, relocation) in group.indexed) {
        final index = relocation.symbol < object.symbols.length
            ? indices[relocation.symbol]!
            : symbols.length + 1 + relocation.symbol - object.symbols.length;
        final type = switch ((relocation.encoding, relocation.indirect)) {
          (.arm64Call26, false) => 283,
          (.arm64Page21, false) => 275,
          (.arm64Page21, true) => 311,
          (.arm64PageOffset12, false) => 277,
          (.arm64LoadPageOffset12, false) => 286,
          (.arm64LoadPageOffset12, true) => 312,
          (.x64Address32 || .x64LoadAddress32, false) => 2,
          (.x64LoadAddress32, true) => 9,
          (.x64Call32, false) =>
            relocation.symbol < object.symbols.length &&
                    object.symbols[relocation.symbol].binding == .local
                ? 2
                : 4,
          _ => throw UnsupportedError('ELF relocation: ${relocation.encoding}'),
        };
        final offset = relocationOffsets[i] + j * 24;
        data.setUint64(offset, relocation.offset, .little);
        data.setUint64(offset + 8, index << 32 | type, .little);
        data.setInt64(
          offset + 16,
          target.architecture == .arm64 ? 0 : -4,
          .little,
        );
      }
    }
    section(
      symbolIndex,
      2,
      0,
      symbolOffset,
      symbolSize,
      link: stringIndex,
      info: 1 + symbols.where((s) => s.binding == .local).length,
      alignment: 8,
      entrySize: 24,
    );
    section(stringIndex, 3, 0, stringOffset, strings.length);
    section(nameIndex, 3, 0, nameOffset, nameBytes.length);
    section(stackIndex, 1, 0, 0, 0);
    return bytes.asUnmodifiableView();
  }
}
