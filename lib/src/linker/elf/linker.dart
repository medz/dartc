import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart' show ElfRecords;
import 'package:dartc/target.dart';

import '../linker.dart';
import '../link_unit.dart';

/// Links ELF64 shared libraries for Linux ARM64 and x86-64.
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
    final object = LinkUnit(target, objects, name);
    const textOffset = 240;
    final symbols = object.symbols.where((symbol) => symbol.exported).toList();
    final count = symbols.length;
    final strings = <int>[0], names = <int>[];
    for (final name in symbols.map((s) => s.name)) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final sonameOffset = strings.length;
    strings.addAll([...utf8.encode(name), 0]);
    final sectionNames =
        '\u0000.text\u0000.dynsym\u0000.dynstr\u0000.shstrtab\u0000.hash\u0000.dynamic\u0000';
    final symbolOffset = (textOffset + object.code.length + 7) & ~7;
    final symbolSize = (count + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final hashOffset = (stringOffset + strings.length + 7) & ~7;
    final bucketCount = symbols.length | 1;
    final hashSize = (2 + bucketCount + symbols.length + 1) * 4;
    final dynamicOffset = (hashOffset + hashSize + 7) & ~7;
    const dynamicSize = 7 * 16;
    final nameOffset = dynamicOffset + dynamicSize;
    final sectionOffset = (nameOffset + sectionNames.length + 7) & ~7;
    const sectionCount = 7;
    final data = ByteData(sectionOffset + sectionCount * 64);
    final bytes = data.buffer.asUint8List();
    data.writeElf64Header(
      architecture: object.target.architecture,
      type: 3,
      sectionOffset: sectionOffset,
      sectionCount: sectionCount,
      sectionNames: 4,
      programCount: 3,
    );
    object.writeCode(data, textOffset, address: textOffset);
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, ascii.encode(sectionNames));
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, 0x12);
      data.setUint16(offset + 6, 1, .little);
      data.setUint64(offset + 8, symbol.offset + textOffset, .little);
      data.setUint64(offset + 16, symbol.size, .little);
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
        address: flags & 2 != 0 ? offset : 0,
        link: link,
        info: info,
        alignment: alignment,
        entrySize: entrySize,
      );
    }

    section(1, '.text', 1, 6, textOffset, object.code.length, alignment: 16);
    section(
      2,
      '.dynsym',
      11,
      2,
      symbolOffset,
      symbolSize,
      link: 3,
      info: 1,
      alignment: 8,
      entrySize: 24,
    );
    section(3, '.dynstr', 3, 2, stringOffset, strings.length);
    section(4, '.shstrtab', 3, 0, nameOffset, sectionNames.length);
    section(
      5,
      '.hash',
      5,
      2,
      hashOffset,
      hashSize,
      link: 2,
      alignment: 8,
      entrySize: 4,
    );
    section(
      6,
      '.dynamic',
      6,
      2,
      dynamicOffset,
      dynamicSize,
      link: 3,
      alignment: 8,
      entrySize: 16,
    );
    void segment(
      int index,
      int type,
      int flags,
      int offset,
      int size,
      int alignment,
    ) {
      final base = 64 + index * 56;
      data.setUint32(base, type, .little);
      data.setUint32(base + 4, flags, .little);
      data.setUint64(base + 8, offset, .little);
      data.setUint64(base + 16, offset, .little);
      data.setUint64(base + 24, offset, .little);
      data.setUint64(base + 32, size, .little);
      data.setUint64(base + 40, size, .little);
      data.setUint64(base + 48, alignment, .little);
    }

    segment(
      0,
      1,
      5,
      0,
      nameOffset,
      object.target.architecture == .arm64 ? 65536 : 4096,
    );
    segment(1, 2, 4, dynamicOffset, dynamicSize, 8);
    segment(
      2,
      0x6474e551,
      6,
      0,
      0,
      16,
    ); // PT_GNU_STACK: read/write, never execute.
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
