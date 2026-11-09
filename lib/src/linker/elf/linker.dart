import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart' show ElfRecords, ElfSectionKind;
import 'package:dartc/target.dart';

import '../linker.dart';
import '../link_unit.dart';

/// Links ELF64 shared libraries with separate executable and writable mappings.
final class ElfLinker(@override final Target target) implements Linker {
  this {
    if (target.operatingSystem != .linux) {
      throw ArgumentError('ELF requires a Linux target.');
    }
  }

  @override
  Uint8List linkSharedLibrary(
    Iterable<ObjectModule> objects, {
    required String name,
  }) {
    final unit = LinkUnit(target, objects, name), sections = unit.sections;
    final symbols = unit.symbols.where((symbol) => symbol.exported).toList();
    final hasConstants = sections.any((s) => s.kind == .readOnlyData);
    final writable = sections.any(
      (s) => s.kind == .data || s.kind == .zeroFill,
    );
    final programCount = 3 + (hasConstants ? 1 : 0) + (writable ? 1 : 0);
    var page = target.architecture == .arm64 ? 65536 : 4096;
    for (final section in sections) {
      if (section.alignment > page) page = section.alignment;
    }
    final offsets = List.filled(sections.length, 0),
        addresses = List.filled(sections.length, 0);
    var cursor = (64 + programCount * 56 + 15) & ~15;
    void place(SectionKind kind) {
      for (final (i, section) in sections.indexed) {
        if (section.kind != kind) continue;
        cursor = (cursor + section.alignment - 1) & -section.alignment;
        RangeError.checkNotNegative(cursor, 'section address');
        offsets[i] = addresses[i] = cursor;
        cursor += section.size;
        RangeError.checkNotNegative(cursor, 'section end');
      }
    }

    place(.code);
    final textEnd = cursor,
        readOnlyStart = hasConstants ? (cursor + page - 1) & -page : cursor;
    cursor = readOnlyStart;
    place(.readOnlyData);
    final strings = <int>[0], names = <int>[];
    for (final symbol in symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    final sonameOffset = strings.length;
    strings.addAll([...utf8.encode(name), 0]);
    final symbolOffset = (cursor + 7) & ~7,
        symbolSize = (symbols.length + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final hashOffset = (stringOffset + strings.length + 7) & ~7;
    final bucketCount = symbols.length | 1;
    final hashSize = (2 + bucketCount + symbols.length + 1) * 4;
    final dynamicOffset = (hashOffset + hashSize + 7) & ~7;
    const dynamicSize = 7 * 16;
    final readOnlyEnd = dynamicOffset + dynamicSize;
    final dataStart = (readOnlyEnd + page - 1) & -page;
    cursor = dataStart;
    place(.data);
    final dataEnd = cursor;
    place(.zeroFill);
    final memoryEnd = cursor;
    final sectionNames = [
      '',
      for (final section in sections) section.kind.elfName,
      '.dynsym',
      '.dynstr',
      '.shstrtab',
      '.hash',
      '.dynamic',
    ];
    final nameBytes = <int>[], nameOffsets = <int>[];
    for (final name in sectionNames) {
      nameOffsets.add(nameBytes.length);
      nameBytes.addAll([...ascii.encode(name), 0]);
    }
    final symbolIndex = sections.length + 1, stringIndex = symbolIndex + 1;
    final nameIndex = symbolIndex + 2,
        hashIndex = symbolIndex + 3,
        dynamicIndex = symbolIndex + 4;
    final nameOffset = writable ? dataEnd : readOnlyEnd;
    final sectionOffset = (nameOffset + nameBytes.length + 7) & ~7;
    final data = ByteData(sectionOffset + sectionNames.length * 64),
        bytes = data.buffer.asUint8List();
    data.writeElf64Header(
      architecture: target.architecture,
      type: 3,
      sectionOffset: sectionOffset,
      sectionCount: sectionNames.length,
      sectionNames: nameIndex,
      programCount: programCount,
    );
    unit.writeSections(data, offsets, addresses);
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, nameBytes);
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, symbol.kind == .function ? 0x12 : 0x11);
      data.setUint16(offset + 6, symbol.section + 1, .little);
      data.setUint64(
        offset + 8,
        addresses[symbol.section] + symbol.offset,
        .little,
      );
      data.setUint64(offset + 16, symbol.size, .little);
    }
    void section(
      int index,
      int type,
      int flags,
      int offset,
      int size, {
      int? address,
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
        address: address ?? (flags & 2 != 0 ? offset : 0),
        link: link,
        info: info,
        alignment: alignment,
        entrySize: entrySize,
      );
    }

    for (final (i, input) in sections.indexed) {
      section(
        i + 1,
        input.kind.elfType,
        input.kind.elfFlags,
        offsets[i],
        input.size,
        address: addresses[i],
        alignment: input.alignment,
      );
    }
    section(
      symbolIndex,
      11,
      2,
      symbolOffset,
      symbolSize,
      link: stringIndex,
      info: 1,
      alignment: 8,
      entrySize: 24,
    );
    section(stringIndex, 3, 2, stringOffset, strings.length);
    section(nameIndex, 3, 0, nameOffset, nameBytes.length);
    section(
      hashIndex,
      5,
      2,
      hashOffset,
      hashSize,
      link: symbolIndex,
      alignment: 8,
      entrySize: 4,
    );
    section(
      dynamicIndex,
      6,
      2,
      dynamicOffset,
      dynamicSize,
      link: stringIndex,
      alignment: 8,
      entrySize: 16,
    );
    void segment(
      int index,
      int type,
      int flags,
      int offset,
      int fileSize,
      int memorySize,
      int alignment,
    ) {
      final base = 64 + index * 56;
      data.setUint32(base, type, .little);
      data.setUint32(base + 4, flags, .little);
      data.setUint64(base + 8, offset, .little);
      data.setUint64(base + 16, offset, .little);
      data.setUint64(base + 24, offset, .little);
      data.setUint64(base + 32, fileSize, .little);
      data.setUint64(base + 40, memorySize, .little);
      data.setUint64(base + 48, alignment, .little);
    }

    final executableEnd = hasConstants ? textEnd : readOnlyEnd;
    segment(0, 1, 5, 0, executableEnd, executableEnd, page);
    var next = 1;
    if (hasConstants) {
      segment(
        next++,
        1,
        4,
        readOnlyStart,
        readOnlyEnd - readOnlyStart,
        readOnlyEnd - readOnlyStart,
        page,
      );
    }
    if (writable) {
      segment(
        next++,
        1,
        6,
        dataStart,
        dataEnd - dataStart,
        memoryEnd - dataStart,
        page,
      );
    }
    segment(next++, 2, 4, dynamicOffset, dynamicSize, dynamicSize, 8);
    segment(next, 0x6474e551, 6, 0, 0, 0, 16);
    data.setUint32(hashOffset, bucketCount, .little);
    data.setUint32(hashOffset + 4, symbols.length + 1, .little);
    for (final (i, name) in names.indexed) {
      var hash = 0;
      for (var cursor = name; strings[cursor] != 0; cursor++) {
        hash = (hash << 4) + strings[cursor];
        final high = hash & 0xf0000000;
        hash = (hash ^ (high >> 24)) & ~high;
      }
      final bucket = hashOffset + 8 + (hash % bucketCount) * 4;
      final chain = hashOffset + 8 + (bucketCount + i + 1) * 4;
      data.setUint32(chain, data.getUint32(bucket, .little), .little);
      data.setUint32(bucket, i + 1, .little);
    }
    final dynamicEntries = [
      (4, hashOffset),
      (5, stringOffset),
      (6, symbolOffset),
      (10, strings.length),
      (11, 24),
      (14, sonameOffset),
      (0, 0),
    ];
    for (final (i, (tag, value)) in dynamicEntries.indexed) {
      data.setUint64(dynamicOffset + i * 16, tag, .little);
      data.setUint64(dynamicOffset + i * 16 + 8, value, .little);
    }
    return bytes.asUnmodifiableView();
  }
}
