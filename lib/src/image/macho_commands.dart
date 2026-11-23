import 'bytes.dart';

/// The unit of memory protection.
const pageBytes = 0x4000;

int pageAlign(int value) => (value + pageBytes - 1) & ~(pageBytes - 1);

const _loader = '/usr/lib/dyld', _system = '/usr/lib/libSystem.B.dylib';
const _headerBytes = 32, _segment = 72, _section = 80, _linkedData = 16;
const _loaderBytes = 32, _systemBytes = 56;

int _commandBytes({required bool imports}) =>
    3 * _segment +
    _section +
    (imports ? _segment + _section + _linkedData : 0) +
    24 +
    80 +
    _loaderBytes +
    24 +
    24 +
    24 +
    _systemBytes +
    _linkedData;

/// The file position after the header and its load commands.
int commandsEnd({required bool imports}) =>
    _headerBytes + _commandBytes(imports: imports);

/// Writes the header and load commands.
///
/// The executable segment starts the file. Import slots, if any, follow on
/// the next page, and then the loader's tables and the signature.
void writeCommands(
  ByteWriter out, {
  required int base,
  required int textOffset,
  required int textEnd,
  required int entryOffset,
  required int slotsBytes,
  required int tableBytes,
  required int signatureOffset,
  required int signatureBytes,
  required List<int> uuid,
}) {
  final imports = slotsBytes > 0;
  final textBytes = pageAlign(textEnd);
  final linkOffset = textBytes + pageAlign(slotsBytes);
  final linkBytes = signatureOffset + signatureBytes - linkOffset;
  out
    ..u32(0xfeedfacf)
    ..u32(0x0100000c) // ARM64.
    ..u32(0)
    ..u32(2) // An executable.
    ..u32(imports ? 13 : 11)
    ..u32(_commandBytes(imports: imports))
    ..u32(0x200085) // No undefined symbols, dyld, two-level, PIE.
    ..u32(0);
  _writeSegment(out, '__PAGEZERO', memoryBytes: base);
  _writeSegment(
    out,
    '__TEXT',
    address: base,
    memoryBytes: textBytes,
    fileBytes: textBytes,
    protection: 5,
    sections: 1,
  );
  _writeSection(
    out,
    '__text',
    '__TEXT',
    address: base + textOffset,
    offset: textOffset,
    bytes: textEnd - textOffset,
    alignment: 4,
    flags: 0x80000400, // Only instructions.
  );
  if (imports) {
    _writeSegment(
      out,
      '__DATA_CONST',
      address: base + textBytes,
      memoryBytes: pageAlign(slotsBytes),
      fileOffset: textBytes,
      fileBytes: pageAlign(slotsBytes),
      protection: 3,
      sections: 1,
      flags: 0x10, // Read-only after binding.
    );
    _writeSection(
      out,
      '__got',
      '__DATA_CONST',
      address: base + textBytes,
      offset: textBytes,
      bytes: slotsBytes,
      alignment: 3,
      flags: 0,
    );
  }
  _writeSegment(
    out,
    '__LINKEDIT',
    address: base + linkOffset,
    memoryBytes: pageAlign(linkBytes),
    fileOffset: linkOffset,
    fileBytes: linkBytes,
    protection: 1,
  );
  if (imports) _writeLinkedData(out, 0x80000034, linkOffset, tableBytes);
  _writeLoaderCommands(out, entryOffset, uuid);
  _writeLinkedData(out, 0x1d, signatureOffset, signatureBytes);
  if (out.length != commandsEnd(imports: imports)) {
    throw StateError('Load commands end at ${out.length}.');
  }
}

void _writeLoaderCommands(ByteWriter out, int entryOffset, List<int> uuid) {
  out
    ..u32(0x2) // LC_SYMTAB, empty.
    ..u32(24)
    ..zeros(16)
    ..u32(0xb) // LC_DYSYMTAB, empty.
    ..u32(80)
    ..zeros(72)
    ..u32(0xe) // LC_LOAD_DYLINKER.
    ..u32(_loaderBytes)
    ..u32(12)
    ..text(_loader, _loaderBytes - 12)
    ..u32(0x1b) // LC_UUID.
    ..u32(24)
    ..bytes(uuid)
    ..u32(0x32) // LC_BUILD_VERSION: macOS 11, no tools.
    ..u32(24)
    ..u32(1)
    ..u32(11 << 16)
    ..u32(11 << 16)
    ..u32(0)
    ..u32(0x80000028) // LC_MAIN.
    ..u32(24)
    ..u64(entryOffset)
    ..u64(0)
    ..u32(0xc) // LC_LOAD_DYLIB.
    ..u32(_systemBytes)
    ..u32(24)
    ..u32(2)
    ..u32(1 << 16)
    ..u32(1 << 16)
    ..text(_system, _systemBytes - 24);
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
  required int address,
  required int offset,
  required int bytes,
  required int alignment,
  required int flags,
}) => out
  ..text(name, 16)
  ..text(segment, 16)
  ..u64(address)
  ..u64(bytes)
  ..u32(offset)
  ..u32(alignment)
  ..zeros(8)
  ..u32(flags)
  ..zeros(12);
