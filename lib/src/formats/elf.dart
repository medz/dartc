import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/artifact.dart';
import 'package:dartc/target.dart';

import 'format.dart';

/// Writes ELF64 objects and shared libraries for Linux ARM64 and x86-64.
final class Elf(@override final Target target) implements ImageFormat {
  this {
    if (target.operatingSystem != .linux) {
      throw ArgumentError('ELF requires a Linux target.');
    }
  }

  @override
  Uint8List encodeObject(ObjectModule module) {
    _checkTarget(module);
    return _encode(module, module.code, null, 64);
  }

  @override
  ImageLayout layoutImage(ObjectModule module, {required String libraryName}) {
    _checkTarget(module);
    if (libraryName.isEmpty || libraryName.contains('\u0000')) {
      throw ArgumentError.value(libraryName, 'libraryName');
    }
    return _ElfLayout(module, libraryName);
  }

  @override
  Uint8List encodeImage(LinkedImage image) {
    final layout = image.layout;
    if (layout is! _ElfLayout) throw ArgumentError('Expected an ELF layout.');
    _checkTarget(layout.module);
    return _encode(layout.module, image.code, layout.soname, layout.codeOffset);
  }

  void _checkTarget(ObjectModule module) {
    if (module.target != target) throw ArgumentError('ELF target mismatch.');
  }

  Uint8List _encode(
    ObjectModule object,
    Uint8List code,
    String? soname,
    int textOffset,
  ) {
    final symbols = soname == null
        ? ([...object.symbols]
            ..sort((a, b) => a.binding.index.compareTo(b.binding.index)))
        : object.symbols.where((s) => s.exported).toList();
    final strings = <int>[0], names = <int>[];
    for (final symbol in symbols) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(symbol.name), 0]);
    }
    final shared = soname != null;
    final sonameOffset = strings.length;
    if (soname != null) strings.addAll([...utf8.encode(soname), 0]);
    final sectionNames = shared
        ? '\u0000.text\u0000.dynsym\u0000.dynstr\u0000.shstrtab\u0000.hash\u0000.dynamic\u0000'
        : '\u0000.text\u0000.symtab\u0000.strtab\u0000.shstrtab\u0000.note.GNU-stack\u0000';
    final symbolOffset = (textOffset + object.code.length + 7) & ~7;
    final symbolSize = (symbols.length + 1) * 24;
    final stringOffset = symbolOffset + symbolSize;
    final hashOffset = (stringOffset + strings.length + 7) & ~7;
    final bucketCount = symbols.length | 1;
    final hashSize = (2 + bucketCount + symbols.length + 1) * 4;
    final dynamicOffset = (hashOffset + hashSize + 7) & ~7;
    const dynamicSize = 7 * 16;
    final nameOffset = shared
        ? dynamicOffset + dynamicSize
        : stringOffset + strings.length;
    final sectionOffset = (nameOffset + sectionNames.length + 7) & ~7;
    final sectionCount = shared ? 7 : 6;
    final data = ByteData(sectionOffset + sectionCount * 64);
    final bytes = data.buffer.asUint8List();
    bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
    data.setUint16(16, shared ? 3 : 1, .little);
    data.setUint16(
      18,
      object.target.architecture == .arm64 ? 183 : 62,
      .little,
    );
    data.setUint32(20, 1, .little);
    data.setUint64(32, shared ? 64 : 0, .little);
    data.setUint64(40, sectionOffset, .little);
    data.setUint16(52, 64, .little);
    data.setUint16(54, shared ? 56 : 0, .little);
    data.setUint16(56, shared ? 3 : 0, .little);
    data.setUint16(58, 64, .little);
    data.setUint16(60, sectionCount, .little);
    data.setUint16(62, 4, .little);
    bytes.setAll(textOffset, code);
    bytes.setAll(stringOffset, strings);
    bytes.setAll(nameOffset, ascii.encode(sectionNames));
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + (i + 1) * 24;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, symbol.binding == .local ? 0x02 : 0x12);
      data.setUint16(offset + 6, 1, .little);
      data.setUint64(
        offset + 8,
        symbol.offset + (shared ? textOffset : 0),
        .little,
      );
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
      final base = sectionOffset + index * 64;
      data.setUint32(base, sectionNames.indexOf('$name\u0000'), .little);
      data.setUint32(base + 4, type, .little);
      data.setUint64(base + 8, flags, .little);
      data.setUint64(base + 16, flags & 2 != 0 && shared ? offset : 0, .little);
      data.setUint64(base + 24, offset, .little);
      data.setUint64(base + 32, size, .little);
      data.setUint32(base + 40, link, .little);
      data.setUint32(base + 44, info, .little);
      data.setUint64(base + 48, alignment, .little);
      data.setUint64(base + 56, entrySize, .little);
    }

    section(1, '.text', 1, 6, textOffset, object.code.length, alignment: 16);
    section(
      2,
      shared ? '.dynsym' : '.symtab',
      shared ? 11 : 2,
      shared ? 2 : 0,
      symbolOffset,
      symbolSize,
      link: 3,
      info: 1 + symbols.where((s) => s.binding == .local).length,
      alignment: 8,
      entrySize: 24,
    );
    section(
      3,
      shared ? '.dynstr' : '.strtab',
      3,
      shared ? 2 : 0,
      stringOffset,
      strings.length,
    );
    section(4, '.shstrtab', 3, 0, nameOffset, sectionNames.length);
    if (shared) {
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
    } else {
      section(5, '.note.GNU-stack', 1, 0, 0, 0);
    }
    return bytes;
  }
}

final class _ElfLayout(@override final ObjectModule module, final String soname)
    implements ImageLayout {
  @override
  int get codeOffset => 240;

  @override
  int get codeAddress => codeOffset;
}
