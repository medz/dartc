import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/mach_o.dart' show MachO, MachOSectionKind;
import 'package:dartc/target.dart';

import '../linker.dart';
import '../input.dart';
import '../link_unit.dart';
import 'code_signature.dart';
import 'export_trie.dart';

/// Links macOS shared libraries, including export metadata and an ad-hoc signature.
final class MachOLinker(@override final Target target) implements Linker {
  this {
    if (target.operatingSystem != .macos) {
      throw ArgumentError('Mach-O requires a macOS target.');
    }
  }

  @override
  Uint8List linkSharedLibrary(
    Iterable<LinkInput> inputs, {
    required String name,
  }) {
    final unit = LinkUnit(MachO(target), inputs, name),
        sections = unit.sections;
    final installName = '@rpath/$name', nameBytes = utf8.encode(installName);
    final idSize = (24 + nameBytes.length + 1 + 7) & ~7;
    const systemLibrary = '/usr/lib/libSystem.B.dylib';
    final libraries = [
      systemLibrary,
      ...unit.libraries.where((name) => name != systemLibrary),
    ];
    if (libraries.length > 253) {
      throw UnsupportedError('Mach-O supports at most 253 library ordinals.');
    }
    final libraryNames = libraries.map(utf8.encode).toList();
    final librarySizes = [
      for (final bytes in libraryNames) (24 + bytes.length + 1 + 7) & ~7,
    ];
    final ordinals = [
      for (final library in unit.libraries) libraries.indexOf(library) + 1,
    ];
    final hasBindings = unit.bindings.isNotEmpty;
    final hasConstants = sections.any((s) => s.kind == .readOnlyData);
    final writable = sections.any(
      (s) => s.kind == .data || s.kind == .zeroFill,
    );
    final segmentCount = 2 + (hasConstants ? 1 : 0) + (writable ? 1 : 0);
    final commandsSize =
        segmentCount * 72 +
        sections.length * 80 +
        idSize +
        librarySizes.fold<int>(0, (sum, size) => sum + size) +
        24 +
        24 +
        24 +
        80 +
        (hasBindings ? 48 : 16) +
        16;
    var page = target.architecture == .arm64 ? 16384 : 4096;
    for (final section in sections) {
      if (section.alignment > page) page = section.alignment;
    }
    final offsets = List.filled(sections.length, 0),
        addresses = List.filled(sections.length, 0);
    var position = (32 + commandsSize + 15) & ~15;
    void place(SectionKind kind) {
      for (final (i, section) in sections.indexed) {
        if (section.kind != kind) continue;
        position = (position + section.alignment - 1) & -section.alignment;
        RangeError.checkNotNegative(position, 'section address');
        addresses[i] = position;
        offsets[i] = kind == .zeroFill ? 0 : position;
        position += section.size;
        RangeError.checkNotNegative(position, 'section end');
      }
    }

    place(.code);
    final textSize = (position + page - 1) & -page;
    position = textSize;
    place(.readOnlyData);
    final dataStart = (position + page - 1) & -page;
    position = dataStart;
    place(.data);
    final dataFileEnd = (position + page - 1) & -page;
    position = dataFileEnd;
    place(.zeroFill);
    final linkAddress = (position + page - 1) & -page;
    RangeError.checkNotNegative(linkAddress, 'link-edit address');
    final linkOffset = dataFileEnd;
    final symbols = unit.symbols.where((s) => s.exported).toList();
    final strings = <int>[0], names = <int>[];
    for (final name in [
      for (final symbol in symbols) symbol.name,
      for (final binding in unit.bindings) binding.name,
    ]) {
      names.add(strings.length);
      strings.addAll([...utf8.encode(name), 0]);
    }
    final stringOffset = linkOffset + names.length * 16;
    final trieOffset = (stringOffset + strings.length + 7) & ~7;
    final trie = ExportTrie([
      for (final symbol in symbols)
        (symbol.name, addresses[symbol.section] + symbol.offset),
    ]).encode();
    final bindOffset = (trieOffset + trie.length + 7) & ~7,
        binds = BytesBuilder();
    void uleb(int value) {
      do {
        final byte = value & 127;
        value >>= 7;
        binds.addByte(byte | (value == 0 ? 0 : 128));
      } while (value != 0);
    }

    for (final binding in unit.bindings) {
      final ordinal = ordinals[binding.library];
      if (ordinal <= 15) {
        binds.addByte(0x10 | ordinal);
      } else {
        binds.addByte(0x20);
        uleb(ordinal);
      }
      binds
        ..addByte(0x40)
        ..add(utf8.encode(binding.name))
        ..add([0, 0x51, 0x70 | (hasConstants ? 2 : 1)]);
      final slot = unit.symbols[binding.slot];
      uleb(addresses[slot.section] + slot.offset - dataStart);
      binds.addByte(0x90);
    }
    if (hasBindings) binds.addByte(0);
    final bindBytes = binds.takeBytes();
    final signatureOffset = (bindOffset + bindBytes.length + 15) & ~15;
    final signature = CodeSignature(installName, signatureOffset, textSize);
    final data = ByteData(signatureOffset + signature.size),
        bytes = data.buffer.asUint8List();
    data.setUint32(0, 0xfeedfacf, .little);
    data.setUint32(
      4,
      target.architecture == .arm64 ? 0x100000c : 0x1000007,
      .little,
    );
    data.setUint32(8, target.architecture == .arm64 ? 0 : 3, .little);
    data.setUint32(12, 6, .little);
    data.setUint32(16, segmentCount + 7 + libraries.length, .little);
    data.setUint32(20, commandsSize, .little);
    data.setUint32(24, 0x85, .little);
    var cursor = 32;
    int command(int kind, int size) {
      final offset = cursor;
      data.setUint32(offset, kind, .little);
      data.setUint32(offset + 4, size, .little);
      cursor += size;
      return offset;
    }

    void segment(
      String name,
      int fileOffset,
      int fileSize,
      int address,
      int memorySize,
      int protection,
      List<int> indices,
    ) {
      final base = command(0x19, 72 + indices.length * 80);
      bytes.setAll(base + 8, ascii.encode(name));
      data.setUint64(base + 24, address, .little);
      data.setUint64(base + 32, memorySize, .little);
      data.setUint64(base + 40, fileOffset, .little);
      data.setUint64(base + 48, fileSize, .little);
      data.setUint32(base + 56, protection, .little);
      data.setUint32(base + 60, protection, .little);
      data.setUint32(base + 64, indices.length, .little);
      for (final (j, i) in indices.indexed) {
        final section = sections[i], offset = base + 72 + j * 80;
        bytes.setAll(offset, ascii.encode(section.kind.machName));
        bytes.setAll(offset + 16, ascii.encode(name));
        data.setUint64(offset + 32, addresses[i], .little);
        data.setUint64(offset + 40, section.size, .little);
        data.setUint32(offset + 48, offsets[i], .little);
        data.setUint32(offset + 52, section.alignment.bitLength - 1, .little);
        data.setUint32(offset + 64, section.kind.machFlags, .little);
      }
    }

    List<int> inSegment(String name) => [
      for (final (i, section) in sections.indexed)
        if (section.kind.machSegment == name) i,
    ];
    segment('__TEXT', 0, textSize, 0, textSize, 5, inSegment('__TEXT'));
    if (hasConstants) {
      segment(
        '__CONST',
        textSize,
        dataStart - textSize,
        textSize,
        dataStart - textSize,
        1,
        inSegment('__CONST'),
      );
    }
    if (writable) {
      segment(
        '__DATA',
        dataStart,
        dataFileEnd - dataStart,
        dataStart,
        linkAddress - dataStart,
        3,
        inSegment('__DATA'),
      );
    }
    segment(
      '__LINKEDIT',
      linkOffset,
      bytes.length - linkOffset,
      linkAddress,
      (bytes.length - linkOffset + page - 1) & -page,
      1,
      [],
    );
    final id = command(0xd, idSize);
    data.setUint32(id + 8, 24, .little);
    data.setUint32(id + 16, 0x10000, .little);
    data.setUint32(id + 20, 0x10000, .little);
    bytes.setAll(id + 24, nameBytes);
    // dyld requires libSystem even when the library imports no symbols.
    for (final (i, library) in libraryNames.indexed) {
      final dependency = command(0xc, librarySizes[i]);
      data.setUint32(dependency + 8, 24, .little);
      data.setUint32(dependency + 16, i == 0 ? 0x10000 : 0, .little);
      data.setUint32(dependency + 20, i == 0 ? 0x10000 : 0, .little);
      bytes.setAll(dependency + 24, library);
    }
    final build = command(0x32, 24);
    data.setUint32(build + 8, 1, .little);
    data.setUint32(build + 12, 0xb0000, .little);
    final uuid = command(0x1b, 24), symtab = command(2, 24);
    data.setUint32(symtab + 8, linkOffset, .little);
    data.setUint32(symtab + 12, names.length, .little);
    data.setUint32(symtab + 16, stringOffset, .little);
    data.setUint32(symtab + 20, strings.length, .little);
    final dysymtab = command(0xb, 80);
    data.setUint32(dysymtab + 20, symbols.length, .little);
    data.setUint32(dysymtab + 24, symbols.length, .little);
    data.setUint32(dysymtab + 28, unit.bindings.length, .little);
    if (hasBindings) {
      final info = command(0x80000022, 48);
      data.setUint32(info + 16, bindOffset, .little);
      data.setUint32(info + 20, bindBytes.length, .little);
      data.setUint32(info + 40, trieOffset, .little);
      data.setUint32(info + 44, trie.length, .little);
    } else {
      final exports = command(0x80000033, 16);
      data.setUint32(exports + 8, trieOffset, .little);
      data.setUint32(exports + 12, trie.length, .little);
    }
    final signing = command(0x1d, 16);
    data.setUint32(signing + 8, signatureOffset, .little);
    data.setUint32(signing + 12, signature.size, .little);
    unit.writeSections(data, offsets, addresses);
    for (final (i, symbol) in symbols.indexed) {
      final offset = linkOffset + i * 16;
      data.setUint32(offset, names[i], .little);
      data.setUint8(offset + 4, 0xf);
      data.setUint8(offset + 5, symbol.section + 1);
      data.setUint64(
        offset + 8,
        addresses[symbol.section] + symbol.offset,
        .little,
      );
    }
    for (final (i, binding) in unit.bindings.indexed) {
      final index = symbols.length + i, offset = linkOffset + index * 16;
      data.setUint32(offset, names[index], .little);
      data.setUint8(offset + 4, 1);
      data.setUint16(offset + 6, ordinals[binding.library] << 8, .little);
    }
    bytes.setAll(stringOffset, strings);
    bytes.setAll(trieOffset, trie);
    bytes.setAll(bindOffset, bindBytes);
    final identifier = sha256
        .convert(Uint8List.sublistView(bytes, 0, signatureOffset))
        .bytes
        .sublist(0, 16);
    identifier[6] = (identifier[6] & 15) | 0x80;
    identifier[8] = (identifier[8] & 63) | 0x80;
    bytes.setAll(uuid + 8, identifier);
    signature.write(bytes);
    return bytes.asUnmodifiableView();
  }
}
