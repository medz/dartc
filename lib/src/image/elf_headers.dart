import 'bytes.dart';

/// The sizes of what ELF files have.
abstract final class ElfHeaders() {
  static const fileBytes = 64, segmentBytes = 56, sectionBytes = 64;
  static const relocationBytes = 24;
}

/// Writes the header of a file, whose last section has the names of all.
void writeElfHeader(
  ByteWriter out, {
  required int type,
  required int machine,
  required int entry,
  required int segments,
  required int sectionsAt,
  required int sections,
}) => out
  ..bytes([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1])
  ..zeros(9)
  ..u16(type)
  ..u16(machine)
  ..u32(1)
  ..u64(entry)
  ..u64(segments == 0 ? 0 : ElfHeaders.fileBytes)
  ..u64(sectionsAt)
  ..u32(0)
  ..u16(ElfHeaders.fileBytes)
  ..u16(segments == 0 ? 0 : ElfHeaders.segmentBytes)
  ..u16(segments)
  ..u16(ElfHeaders.sectionBytes)
  ..u16(sections)
  ..u16(sections - 1);

void writeElfSegment(
  ByteWriter out, {
  required int type,
  required int flags,
  required int offset,
  required int address,
  required int fileBytes,
  required int memoryBytes,
  required int alignment,
}) => out
  ..u32(type)
  ..u32(flags)
  ..u64(offset)
  ..u64(address)
  ..u64(address)
  ..u64(fileBytes)
  ..u64(memoryBytes)
  ..u64(alignment);

void writeElfSection(
  ByteWriter out, {
  required int name,
  required int type,
  required int flags,
  required int address,
  required int offset,
  required int bytes,
  required int alignment,
  int link = 0,
  int info = 0,
  int entryBytes = 0,
}) => out
  ..u32(name)
  ..u32(type)
  ..u64(flags)
  ..u64(address)
  ..u64(offset)
  ..u64(bytes)
  ..u32(link)
  ..u32(info)
  ..u64(alignment)
  ..u64(entryBytes);
