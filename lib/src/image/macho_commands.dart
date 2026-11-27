import 'dart:convert';

import 'bytes.dart';
import 'layout.dart';
import 'link_tables.dart';

const _loader = '/usr/lib/dyld', _system = '/usr/lib/libSystem.B.dylib';
const _headerBytes = 32, _segment = 72, _section = 80, _linkedData = 16;
const _loaderBytes = 32, _systemBytes = 56;

/// What an image is for.
sealed class const MachoKind();

/// A program that starts with the function [entry].
final class const MachoExecutable(final String entry) extends MachoKind;

/// A library that programs load as [name].
final class const MachoLibrary(final String name) extends MachoKind;

int _libraryBytes(String name) => 24 + (utf8.encode(name).length + 8) ~/ 8 * 8;

int _commandBytes(
  MachoKind kind, {
  required bool hasConstants,
  required bool hasImports,
  required bool hasConstObjects,
  required bool hasData,
  required bool hasFixups,
}) {
  final hasDataConst = hasImports || hasConstObjects;
  final segments =
      (kind is MachoExecutable ? 3 : 2) +
      (hasDataConst ? 1 : 0) +
      (hasData ? 1 : 0);
  final sections = [
    true,
    hasConstants,
    hasImports,
    hasConstObjects,
    hasData,
  ].where((exists) => exists).length;
  return segments * _segment +
      sections * _section +
      (hasFixups ? _linkedData : 0) +
      24 +
      80 +
      switch (kind) {
        MachoExecutable() => _loaderBytes + 24,
        MachoLibrary(:final name) => _libraryBytes(name) + _linkedData,
      } +
      24 +
      24 +
      _systemBytes +
      _linkedData;
}

/// The file position after the header and its load commands.
int commandsEnd(
  MachoKind kind, {
  required bool hasConstants,
  required bool hasImports,
  required bool hasConstObjects,
  required bool hasData,
  required bool hasFixups,
}) =>
    _headerBytes +
    _commandBytes(
      kind,
      hasConstants: hasConstants,
      hasImports: hasImports,
      hasConstObjects: hasConstObjects,
      hasData: hasData,
      hasFixups: hasFixups,
    );

/// Writes the header and load commands.
void writeCommands(
  ByteWriter out,
  MachoKind kind,
  MachoLayout layout,
  LinkTables links, {
  required int base,
  required int entryOffset,
  required int signatureOffset,
  required int signatureBytes,
  required List<int> uuid,
}) {
  final end = commandsEnd(
    kind,
    hasConstants: layout.hasConstants,
    hasImports: layout.importCount > 0,
    hasConstObjects: layout.constObjectBytes > 0,
    hasData: layout.hasData,
    hasFixups: layout.hasFixups,
  );
  final linkBytes = signatureOffset + signatureBytes - layout.linkOffset;
  final isLibrary = kind is MachoLibrary;
  out
    ..u32(0xfeedfacf)
    ..u32(0x0100000c) // ARM64.
    ..u32(0)
    ..u32(isLibrary ? 6 : 2)
    ..u32(layout.segments + 8 + (layout.hasFixups ? 1 : 0))
    ..u32(end - _headerBytes)
    // No undefined symbols, dyld, two-level, and position-independent or
    // without libraries of its own to offer.
    ..u32(isLibrary ? 0x100085 : 0x200085)
    ..u32(0);
  if (layout.hasZeroPage) _writeSegment(out, '__PAGEZERO', memoryBytes: base);
  _writeText(out, layout, base);
  if (layout.hasDataConst) _writeDataConst(out, layout, base);
  if (layout.hasData) _writeData(out, layout, base);
  _writeSegment(
    out,
    '__LINKEDIT',
    address: base + layout.linkOffset,
    memoryBytes: pageAlign(linkBytes),
    fileOffset: layout.linkOffset,
    fileBytes: linkBytes,
    protection: 1,
  );
  if (kind case MachoLibrary(:final name)) _writeLibrary(out, 0xd, name);
  final at = layout.linkOffset;
  if (layout.hasFixups) {
    _writeLinkedData(out, 0x80000034, at, links.fixups.length);
  }
  if (isLibrary) {
    final bytes = links.exports.length;
    _writeLinkedData(out, 0x80000033, at + links.exportsOffset, bytes);
  }
  _writeSymbolTable(out, links, at);
  _writeLoaderCommands(out, kind, entryOffset, uuid);
  _writeLinkedData(out, 0x1d, signatureOffset, signatureBytes);
  if (out.length != end) {
    throw StateError('Load commands end at ${out.length}.');
  }
}

/// A command about the library [name]: this one, or one to load.
void _writeLibrary(ByteWriter out, int command, String name) {
  final bytes = _libraryBytes(name);
  out
    ..u32(command)
    ..u32(bytes)
    ..u32(24)
    ..u32(2)
    ..u32(1 << 16)
    ..u32(1 << 16)
    ..text(name, bytes - 24);
}

void _writeSymbolTable(ByteWriter out, LinkTables links, int start) {
  final count = links.symbolCount;
  out
    ..u32(0x2) // LC_SYMTAB.
    ..u32(24);
  if (count == 0) {
    out.zeros(16);
  } else {
    out
      ..u32(start + links.symbolsOffset)
      ..u32(count)
      ..u32(start + links.namesOffset)
      ..u32(links.symbolTable.names.length);
  }
  final local = links.localCount;
  out
    ..u32(0xb) // LC_DYSYMTAB: local symbols, then defined external ones.
    ..u32(80)
    ..u32(0)
    ..u32(local)
    ..u32(local)
    ..u32(count - local)
    ..u32(count)
    ..zeros(52);
}

void _writeText(ByteWriter out, MachoLayout layout, int base) {
  _writeSegment(
    out,
    '__TEXT',
    address: base,
    memoryBytes: layout.dataConstOffset,
    fileBytes: layout.dataConstOffset,
    protection: 5,
    sections: layout.hasConstants ? 2 : 1,
  );
  _writeSection(
    out,
    '__text',
    '__TEXT',
    base: base,
    offset: layout.textOffset,
    bytes: layout.textEnd - layout.textOffset,
    alignment: 4,
    flags: 0x80000400, // Only instructions.
  );
  if (!layout.hasConstants) return;
  _writeSection(
    out,
    '__const',
    '__TEXT',
    base: base,
    offset: layout.constantsOffset,
    bytes: layout.constantBytes,
    alignment: 4,
  );
}

void _writeDataConst(ByteWriter out, MachoLayout layout, int base) {
  final hasImports = layout.importCount > 0;
  final hasObjects = layout.constObjectBytes > 0;
  _writeSegment(
    out,
    '__DATA_CONST',
    address: base + layout.dataConstOffset,
    memoryBytes: pageAlign(layout.dataConstBytes),
    fileOffset: layout.dataConstOffset,
    fileBytes: pageAlign(layout.dataConstBytes),
    protection: 3,
    sections: hasImports && hasObjects ? 2 : 1,
    flags: 0x10, // Read-only once filled in.
  );
  if (hasImports) {
    _writeSection(
      out,
      '__got',
      '__DATA_CONST',
      base: base,
      offset: layout.dataConstOffset,
      bytes: layout.slotsBytes,
      alignment: 3,
    );
  }
  if (!hasObjects) return;
  _writeSection(
    out,
    '__const',
    '__DATA_CONST',
    base: base,
    offset: layout.constObjectsOffset,
    bytes: layout.constObjectBytes,
    alignment: 4,
  );
}

void _writeData(ByteWriter out, MachoLayout layout, int base) {
  _writeSegment(
    out,
    '__DATA',
    address: base + layout.dataOffset,
    memoryBytes: pageAlign(layout.dataBytes),
    fileOffset: layout.dataOffset,
    fileBytes: pageAlign(layout.dataBytes),
    protection: 3,
    sections: 1,
  );
  _writeSection(
    out,
    '__data',
    '__DATA',
    base: base,
    offset: layout.dataOffset,
    bytes: layout.dataBytes,
    alignment: 4,
  );
}

void _writeLoaderCommands(
  ByteWriter out,
  MachoKind kind,
  int entryOffset,
  List<int> uuid,
) {
  if (kind is MachoExecutable) {
    out
      ..u32(0xe) // LC_LOAD_DYLINKER.
      ..u32(_loaderBytes)
      ..u32(12)
      ..text(_loader, _loaderBytes - 12);
  }
  out
    ..u32(0x1b) // LC_UUID.
    ..u32(24)
    ..bytes(uuid)
    ..u32(0x32) // LC_BUILD_VERSION: macOS 11, no tools.
    ..u32(24)
    ..u32(1)
    ..u32(11 << 16)
    ..u32(11 << 16)
    ..u32(0);
  if (kind is MachoExecutable) {
    out
      ..u32(0x80000028) // LC_MAIN.
      ..u32(24)
      ..u64(entryOffset)
      ..u64(0);
  }
  _writeLibrary(out, 0xc, _system);
}

/// A command naming a range of the last segment.
void _writeLinkedData(ByteWriter out, int command, int offset, int bytes) => out
  ..u32(command)
  ..u32(_linkedData)
  ..u32(offset)
  ..u32(bytes);

void _writeSegment(
  ByteWriter out,
  String name, {
  int address = 0,
  required int memoryBytes,
  int fileOffset = 0,
  int fileBytes = 0,
  int protection = 0,
  int sections = 0,
  int flags = 0,
}) => out
  ..u32(0x19)
  ..u32(_segment + sections * _section)
  ..text(name, 16)
  ..u64(address)
  ..u64(memoryBytes)
  ..u64(fileOffset)
  ..u64(fileBytes)
  ..u32(protection)
  ..u32(protection)
  ..u32(sections)
  ..u32(flags);

void _writeSection(
  ByteWriter out,
  String name,
  String segment, {
  required int base,
  required int offset,
  required int bytes,
  required int alignment,
  int flags = 0,
}) => out
  ..text(name, 16)
  ..text(segment, 16)
  ..u64(base + offset)
  ..u64(bytes)
  ..u32(offset)
  ..u32(alignment)
  ..zeros(8)
  ..u32(flags)
  ..zeros(12);
