import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart'
    show Elf, ElfRecords, ElfSectionKind, ElfSymbolKind;
import 'package:dartc/target.dart';

import '../linker.dart';
import '../input.dart';
import '../link_unit.dart';

/// Links ELF64 executables and libraries with separate code and data mappings.
final class ElfLinker(@override final Target target) implements Linker {
  this {
    if (target.operatingSystem != .linux) {
      throw ArgumentError('ELF requires a Linux target.');
    }
  }

  @override
  Uint8List linkSharedLibrary(
    Iterable<LinkInput> inputs, {
    required String name,
  }) => _link(inputs, name: name);

  @override
  Uint8List linkExecutable(
    Iterable<LinkInput> inputs, {
    required String entry,
  }) => _link(inputs, name: entry, entry: entry);

  Uint8List _link(
    Iterable<LinkInput> inputs, {
    required String name,
    String? entry,
  }) {
    final unit = LinkUnit(Elf(target), inputs, name, entry: entry),
        sections = unit.sections;
    final start = entry == null ? null : unit.entryPoint(entry);
    if (start != null && unit.libraries.isNotEmpty) {
      throw UnsupportedError(
        'Linux executables currently require static link inputs.',
      );
    }
    final rebases = start == null
        ? unit.rebases
        : const <({int section, int offset, int target})>[];
    final relocateConstants = start == null && unit.hasReadOnlyFixups;
    final relocationCount = unit.bindings.length + rebases.length;
    final symbols = unit.symbols.where((symbol) => symbol.exported).toList();
    final hasConstants = sections.any((s) => s.kind == .readOnlyData);
    final writable = sections.any(
      (s) => s.kind == .data || s.kind == .zeroFill,
    );
    final programCount =
        3 +
        (hasConstants ? 1 : 0) +
        (writable ? 1 : 0) +
        (relocateConstants ? 1 : 0);
    var page = target.architecture == .arm64 ? 65536 : 4096;
    for (final section in sections) {
      if (section.alignment > page) page = section.alignment;
    }
    final imageBase = start == null ? 0 : (0x400000 + page - 1) & -page;
    final offsets = List.filled(sections.length, 0),
        addresses = List.filled(sections.length, 0);
    var cursor = (64 + programCount * 56 + 15) & ~15;
    void place(SectionKind kind) {
      for (final (i, section) in sections.indexed) {
        if (section.kind != kind) continue;
        cursor = (cursor + section.alignment - 1) & -section.alignment;
        RangeError.checkNotNegative(cursor, 'section address');
        offsets[i] = cursor;
        addresses[i] = imageBase + cursor;
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
    for (final name in [
      for (final symbol in symbols) symbol.name,
      for (final binding in unit.bindings) binding.name,
    ]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final sonameOffset = strings.length;
    strings.addAll([...utf8.encode(name), 0]);
    final dependencies = <int>[];
    for (final library in unit.libraries) {
      dependencies.add(strings.length);
      strings.addAll([...utf8.encode(library), 0]);
    }
    final symbolOffset = (cursor + 7) & ~7,
        symbolSize = (names.length + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final hashOffset = (stringOffset + strings.length + 7) & ~7;
    final bucketCount = names.length | 1;
    final hashSize = (2 + bucketCount + names.length + 1) * 4;
    final relocationOffset = (hashOffset + hashSize + 7) & ~7;
    final relocationSize = relocationCount * 24;
    final dynamicOffset = relocationOffset + relocationSize;
    final dynamicSize =
        (7 + dependencies.length + (relocationCount == 0 ? 0 : 3)) * 16;
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
      if (relocationCount != 0) '.rela.dyn',
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
      type: start == null ? 3 : 2,
      entryAddress: start == null ? 0 : addresses[start.section] + start.offset,
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
      data.setUint8(offset + 4, 0x10 | symbol.kind.elfType);
      data.setUint16(offset + 6, symbol.section + 1, .little);
      data.setUint64(
        offset + 8,
        addresses[symbol.section] + symbol.offset,
        .little,
      );
      data.setUint64(offset + 16, symbol.size ?? 0, .little);
    }
    for (final (i, binding) in unit.bindings.indexed) {
      final index = symbols.length + i + 1;
      data.setUint32(symbolOffset + index * 24, names[index - 1], .little);
      data.setUint8(symbolOffset + index * 24 + 4, 0x10 | binding.kind.elfType);
      data.setUint64(
        relocationOffset + i * 24,
        addresses[binding.section] + binding.offset,
        .little,
      );
      data.setUint64(
        relocationOffset + i * 24 + 8,
        (index << 32) | (target.architecture == .arm64 ? 1025 : 6),
        .little,
      );
    }
    for (final (i, rebase) in rebases.indexed) {
      final at = relocationOffset + (unit.bindings.length + i) * 24;
      final symbol = unit.symbols[rebase.target];
      data.setUint64(at, addresses[rebase.section] + rebase.offset, .little);
      data.setUint64(at + 8, target.architecture == .arm64 ? 1027 : 8, .little);
      data.setInt64(
        at + 16,
        addresses[symbol.section] + symbol.offset,
        .little,
      );
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
        address: address ?? (flags & 2 != 0 ? imageBase + offset : 0),
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
    if (relocationCount != 0) {
      section(
        dynamicIndex + 1,
        4,
        2,
        relocationOffset,
        relocationSize,
        link: symbolIndex,
        alignment: 8,
        entrySize: 24,
      );
    }
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
      data.setUint64(base + 16, imageBase + offset, .little);
      data.setUint64(base + 24, imageBase + offset, .little);
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
        relocateConstants ? 6 : 4,
        readOnlyStart,
        readOnlyEnd - readOnlyStart,
        (relocateConstants ? dataStart : readOnlyEnd) - readOnlyStart,
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
    segment(next++, 0x6474e551, 6, 0, 0, 0, 16);
    if (relocateConstants) {
      segment(
        next,
        0x6474e552,
        4,
        readOnlyStart,
        readOnlyEnd - readOnlyStart,
        dataStart - readOnlyStart,
        1,
      );
    }
    data.setUint32(hashOffset, bucketCount, .little);
    data.setUint32(hashOffset + 4, names.length + 1, .little);
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
      (4, imageBase + hashOffset),
      (5, imageBase + stringOffset),
      (6, imageBase + symbolOffset),
      (10, strings.length),
      (11, 24),
      (14, sonameOffset),
      for (final dependency in dependencies) (1, dependency),
      if (relocationCount != 0) ...[
        (7, relocationOffset),
        (8, relocationSize),
        (9, 24),
      ],
      (0, 0),
    ];
    for (final (i, (tag, value)) in dynamicEntries.indexed) {
      data.setUint64(dynamicOffset + i * 16, tag, .little);
      data.setUint64(dynamicOffset + i * 16 + 8, value, .little);
    }
    return bytes.asUnmodifiableView();
  }
}
