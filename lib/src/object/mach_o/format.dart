import 'dart:convert';
import 'dart:typed_data';

import 'package:dartc/target.dart';

import '../object_module.dart';
import '../object_format.dart';
import 'sections.dart';
import 'reader.dart';

/// Reads and writes Mach-O relocatable objects for macOS ARM64 and x86-64.
final class MachO(@override final Target target) implements ObjectFormat {
  this {
    if (target.operatingSystem != .macos) {
      throw ArgumentError('Mach-O requires a macOS target.');
    }
  }

  @override
  ObjectModule decodeObject(Uint8List bytes) =>
      MachOReader(target, bytes).read();

  @override
  Uint8List encodeObject(ObjectModule object) {
    if (object.target != target) throw ArgumentError('Mach-O target mismatch.');
    final sections = object.sections;
    if (sections.length > 255) {
      throw UnsupportedError('Mach-O symbol section index exceeds eight bits.');
    }
    final order = List.generate(object.symbols.length, (i) => i)
      ..sort(
        (a, b) => object.symbols[a].binding.index.compareTo(
          object.symbols[b].binding.index,
        ),
      );
    final symbols = [for (final i in order) object.symbols[i]];
    final indices = {for (final (i, original) in order.indexed) original: i};
    final localCount = symbols.where((s) => s.binding == .local).length;
    final count = symbols.length + object.imports.length;
    if (count > 0x1000000) {
      throw UnsupportedError('Mach-O relocation symbol index exceeds 24 bits.');
    }
    final strings = <int>[0], names = <int>[];
    for (final name in [...symbols.map((s) => s.name), ...object.imports]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final segmentSize = 72 + sections.length * 80;
    final commandSize = segmentSize + 24 + 24 + 80;
    var alignment = 16;
    for (final section in sections) {
      if (section.alignment > alignment) alignment = section.alignment;
    }
    final contentOffset = (32 + commandSize + alignment - 1) & -alignment;
    final addresses = List.filled(sections.length, 0);
    var memorySize = 0, fileSize = 0;
    for (final zeroFill in [false, true]) {
      for (final (i, section) in sections.indexed) {
        if ((section.kind == .zeroFill) != zeroFill) continue;
        memorySize = (memorySize + section.alignment - 1) & -section.alignment;
        RangeError.checkNotNegative(memorySize, 'section address');
        addresses[i] = memorySize;
        memorySize += section.size;
        RangeError.checkNotNegative(memorySize, 'section end');
      }
      if (!zeroFill) fileSize = memorySize;
    }
    final groups = [
      for (var i = 0; i < sections.length; i++)
        object.relocations.where((r) => r.section == i).toList()
          ..sort((a, b) => b.offset.compareTo(a.offset)),
    ];
    final relocationOffsets = <int>[];
    var cursor = (contentOffset + fileSize + 7) & ~7;
    for (final group in groups) {
      relocationOffsets.add(cursor);
      cursor += group.length * 8;
    }
    final symbolOffset = cursor, stringOffset = symbolOffset + count * 16;
    final data = ByteData(stringOffset + strings.length);
    final bytes = data.buffer.asUint8List();
    data.setUint32(0, 0xfeedfacf, .little);
    data.setUint32(
      4,
      target.architecture == .arm64 ? 0x100000c : 0x1000007,
      .little,
    );
    data.setUint32(8, target.architecture == .arm64 ? 0 : 3, .little);
    data.setUint32(12, 1, .little);
    data.setUint32(16, 4, .little);
    data.setUint32(20, commandSize, .little);
    data.setUint32(24, 0x2000, .little);
    data.setUint32(32, 0x19, .little);
    data.setUint32(36, segmentSize, .little);
    data.setUint64(64, memorySize, .little);
    data.setUint64(72, contentOffset, .little);
    data.setUint64(80, fileSize, .little);
    data.setUint32(88, 7, .little);
    data.setUint32(92, 7, .little);
    data.setUint32(96, sections.length, .little);
    for (final (i, section) in sections.indexed) {
      final base = 104 + i * 80, group = groups[i];
      bytes.setAll(base, ascii.encode(section.kind.machName));
      bytes.setAll(base + 16, ascii.encode(section.kind.machSegment));
      data.setUint64(base + 32, addresses[i], .little);
      data.setUint64(base + 40, section.size, .little);
      data.setUint32(
        base + 48,
        section.kind == .zeroFill ? 0 : contentOffset + addresses[i],
        .little,
      );
      data.setUint32(base + 52, section.alignment.bitLength - 1, .little);
      data.setUint32(
        base + 56,
        group.isEmpty ? 0 : relocationOffsets[i],
        .little,
      );
      data.setUint32(base + 60, group.length, .little);
      data.setUint32(base + 64, section.kind.machFlags, .little);
      if (section.kind != .zeroFill) {
        bytes.setAll(contentOffset + addresses[i], section.bytes);
      }
      for (final (j, relocation) in group.indexed) {
        final index = relocation.symbol < object.symbols.length
            ? indices[relocation.symbol]!
            : symbols.length + relocation.symbol - object.symbols.length;
        final type = switch ((relocation.encoding, relocation.indirect)) {
          (.arm64Call26 || .x64Call32, false) => 0x2d000000,
          (.arm64Page21, false) => 0x3d000000,
          (.arm64Page21, true) => 0x5d000000,
          (.arm64PageOffset12 || .arm64LoadPageOffset12, false) => 0x4c000000,
          (.arm64LoadPageOffset12, true) => 0x6c000000,
          (.x64Address32 || .x64LoadAddress32, false) => 0x1d000000,
          (.x64LoadAddress32, true) => 0x3d000000,
          _ => throw UnsupportedError(
            'Mach-O relocation: ${relocation.encoding}',
          ),
        };
        data.setUint32(
          relocationOffsets[i] + j * 8,
          relocation.offset,
          .little,
        );
        data.setUint32(relocationOffsets[i] + j * 8 + 4, index | type, .little);
      }
    }
    final build = 32 + segmentSize, symtab = build + 24, dysymtab = symtab + 24;
    data.setUint32(build, 0x32, .little);
    data.setUint32(build + 4, 24, .little);
    data.setUint32(build + 8, 1, .little);
    data.setUint32(build + 12, 0xb0000, .little);
    data.setUint32(symtab, 2, .little);
    data.setUint32(symtab + 4, 24, .little);
    data.setUint32(symtab + 8, symbolOffset, .little);
    data.setUint32(symtab + 12, count, .little);
    data.setUint32(symtab + 16, stringOffset, .little);
    data.setUint32(symtab + 20, strings.length, .little);
    data.setUint32(dysymtab, 0xb, .little);
    data.setUint32(dysymtab + 4, 80, .little);
    data.setUint32(dysymtab + 12, localCount, .little);
    data.setUint32(dysymtab + 16, localCount, .little);
    data.setUint32(dysymtab + 20, symbols.length - localCount, .little);
    data.setUint32(dysymtab + 24, symbols.length, .little);
    data.setUint32(dysymtab + 28, object.imports.length, .little);
    bytes.setAll(stringOffset, strings);
    for (final (i, symbol) in symbols.indexed) {
      final offset = symbolOffset + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(
        offset + 4,
        symbol.binding == .local ? 0xe : (symbol.exported ? 0xf : 0x1f),
      );
      data.setUint8(offset + 5, symbol.section + 1);
      data.setUint64(
        offset + 8,
        addresses[symbol.section] + symbol.offset,
        .little,
      );
    }
    for (final (i, _) in object.imports.indexed) {
      final offset = symbolOffset + (symbols.length + i) * 16;
      data.setUint32(offset, names[symbols.length + i], .little);
      data.setUint8(offset + 4, 1);
    }
    return bytes.asUnmodifiableView();
  }
}
