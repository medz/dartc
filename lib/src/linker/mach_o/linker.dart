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

/// Links macOS executables and libraries with export metadata and ad-hoc signing.
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
    final unit = LinkUnit(MachO(target), inputs, name, entry: entry),
        sections = unit.sections;
    final start = entry == null ? null : unit.entryPoint(entry);
    final imageBase = start == null ? 0 : 0x100000000;
    final relocateConstants = unit.hasReadOnlyFixups;
    final pageZero = start == null ? 0 : 1;
    final installName = start == null ? '@rpath/$name' : name,
        nameBytes = utf8.encode(installName);
    final idSize = start == null ? (24 + nameBytes.length + 1 + 7) & ~7 : 56;
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
    final hasFixups = unit.bindings.isNotEmpty || unit.rebases.isNotEmpty;
    final hasConstants = sections.any((s) => s.kind == .readOnlyData);
    final writable = sections.any(
      (s) => s.kind == .data || s.kind == .zeroFill || s.kind == .finalizers,
    );
    final segmentCount =
        2 + pageZero + (hasConstants ? 1 : 0) + (writable ? 1 : 0);
    final commandsSize =
        segmentCount * 72 +
        sections.length * 80 +
        idSize +
        librarySizes.fold<int>(0, (sum, size) => sum + size) +
        24 +
        24 +
        24 +
        80 +
        (hasFixups ? 48 : 16) +
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
        addresses[i] = imageBase + position;
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
    place(.finalizers);
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
        (symbol.name, addresses[symbol.section] + symbol.offset - imageBase),
    ]).encode();
    final rebaseOffset = (trieOffset + trie.length + 7) & ~7;
    void uleb(BytesBuilder bytes, int value) {
      do {
        final byte = value & 127;
        value >>= 7;
        bytes.addByte(byte | (value == 0 ? 0 : 128));
      } while (value != 0);
    }

    final rebases = BytesBuilder();
    (int, int) fixupPosition(int section, int offset) {
      final constant = sections[section].kind == .readOnlyData;
      return (
        pageZero + (constant || !hasConstants ? 1 : 2),
        addresses[section] +
            offset -
            imageBase -
            (constant ? textSize : dataStart),
      );
    }

    for (final rebase in unit.rebases) {
      final (segment, offset) = fixupPosition(rebase.section, rebase.offset);
      rebases.add([0x11, 0x20 | segment]);
      uleb(rebases, offset);
      rebases.addByte(0x51);
    }
    if (unit.rebases.isNotEmpty) rebases.addByte(0);
    final rebaseBytes = rebases.takeBytes();
    final bindOffset = (rebaseOffset + rebaseBytes.length + 7) & ~7;
    final binds = BytesBuilder();
    for (final binding in unit.bindings) {
      final (segment, offset) = fixupPosition(binding.section, binding.offset);
      final ordinal = ordinals[binding.library];
      if (ordinal <= 15) {
        binds.addByte(0x10 | ordinal);
      } else {
        binds.addByte(0x20);
        uleb(binds, ordinal);
      }
      binds
        ..addByte(0x40)
        ..add(utf8.encode(binding.name))
        ..add([0, 0x51, 0x70 | segment]);
      uleb(binds, offset);
      binds.addByte(0x90);
    }
    if (unit.bindings.isNotEmpty) binds.addByte(0);
    final bindBytes = binds.takeBytes();
    final signatureOffset = (bindOffset + bindBytes.length + 15) & ~15;
    final signature = CodeSignature(
      installName,
      signatureOffset,
      textSize,
      executable: start != null,
    );
    final data = ByteData(signatureOffset + signature.size),
        bytes = data.buffer.asUint8List();
    data.setUint32(0, 0xfeedfacf, .little);
    data.setUint32(
      4,
      target.architecture == .arm64 ? 0x100000c : 0x1000007,
      .little,
    );
    data.setUint32(8, target.architecture == .arm64 ? 0 : 3, .little);
    data.setUint32(12, start == null ? 6 : 2, .little);
    data.setUint32(16, segmentCount + 7 + pageZero + libraries.length, .little);
    data.setUint32(20, commandsSize, .little);
    data.setUint32(24, start == null ? 0x85 : 0x200085, .little);
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
      List<int> indices, {
      bool readOnlyAfterFixups = false,
    }) {
      final base = command(0x19, 72 + indices.length * 80);
      bytes.setAll(base + 8, ascii.encode(name));
      data.setUint64(base + 24, address, .little);
      data.setUint64(base + 32, memorySize, .little);
      data.setUint64(base + 40, fileOffset, .little);
      data.setUint64(base + 48, fileSize, .little);
      data.setUint32(base + 56, protection, .little);
      data.setUint32(base + 60, protection, .little);
      data.setUint32(base + 64, indices.length, .little);
      if (readOnlyAfterFixups) data.setUint32(base + 68, 0x10, .little);
      for (final (j, i) in indices.indexed) {
        final section = sections[i], offset = base + 72 + j * 80;
        bytes.setAll(
          offset,
          ascii.encode(
            section.kind == .finalizers
                ? '__mod_init_func'
                : section.kind.machName,
          ),
        );
        bytes.setAll(offset + 16, ascii.encode(name));
        data.setUint64(offset + 32, addresses[i], .little);
        data.setUint64(offset + 40, section.size, .little);
        data.setUint32(offset + 48, offsets[i], .little);
        data.setUint32(offset + 52, section.alignment.bitLength - 1, .little);
        data.setUint32(
          offset + 64,
          section.kind == .finalizers ? 0x9 : section.kind.machFlags,
          .little,
        );
      }
    }

    List<int> inSegment(String name) => [
      for (final (i, section) in sections.indexed)
        if (section.kind.machSegment == name) i,
    ];
    if (start != null) segment('__PAGEZERO', 0, 0, 0, imageBase, 0, []);
    segment('__TEXT', 0, textSize, imageBase, textSize, 5, inSegment('__TEXT'));
    if (hasConstants) {
      segment(
        relocateConstants ? '__DATA_CONST' : '__CONST',
        textSize,
        dataStart - textSize,
        imageBase + textSize,
        dataStart - textSize,
        relocateConstants ? 3 : 1,
        inSegment('__CONST'),
        readOnlyAfterFixups: relocateConstants,
      );
    }
    if (writable) {
      segment(
        '__DATA',
        dataStart,
        dataFileEnd - dataStart,
        imageBase + dataStart,
        linkAddress - dataStart,
        3,
        inSegment('__DATA'),
      );
    }
    segment(
      '__LINKEDIT',
      linkOffset,
      bytes.length - linkOffset,
      imageBase + linkAddress,
      (bytes.length - linkOffset + page - 1) & -page,
      1,
      [],
    );
    if (start == null) {
      final id = command(0xd, idSize);
      data.setUint32(id + 8, 24, .little);
      data.setUint32(id + 16, 0x10000, .little);
      data.setUint32(id + 20, 0x10000, .little);
      bytes.setAll(id + 24, nameBytes);
    } else {
      final main = command(0x80000028, 24);
      data.setUint64(main + 8, offsets[start.section] + start.offset, .little);
      final loader = command(0xe, 32);
      data.setUint32(loader + 8, 12, .little);
      bytes.setAll(loader + 12, ascii.encode('/usr/lib/dyld'));
    }
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
    if (hasFixups) {
      final info = command(0x80000022, 48);
      if (unit.rebases.isNotEmpty) {
        data.setUint32(info + 8, rebaseOffset, .little);
        data.setUint32(info + 12, rebaseBytes.length, .little);
      }
      if (unit.bindings.isNotEmpty) {
        data.setUint32(info + 16, bindOffset, .little);
        data.setUint32(info + 20, bindBytes.length, .little);
      }
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
    bytes.setAll(rebaseOffset, rebaseBytes);
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
