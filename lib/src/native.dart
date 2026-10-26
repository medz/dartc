import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Direct ARM64 instruction encoding and Mach-O packaging; no assembler/linker.
// Each print writes its UTF-8 string plus newline to stdout, then main exits.
({Uint8List bytes, int codeSize, int stringSize}) generateNative(
  List<String> statements,
) {
  const base = 0x100000000;
  const pageSize = 0x4000;
  const codeOffset = 0x400;
  final instructions = <int>[];
  final strings = BytesBuilder(copy: false);
  final addresses = <({int instruction, int stringOffset})>[];

  void mov(int register, int value) {
    instructions.add(0xd2800000 | ((value & 0xffff) << 5) | register);
    for (var shift = 16; shift < 64; shift += 16) {
      final part = (value >> shift) & 0xffff;
      if (part != 0) {
        instructions.add(
          0xf2800000 | ((shift ~/ 16) << 21) | (part << 5) | register,
        );
      }
    }
  }

  for (final text in statements) {
    final message = utf8.encode('$text\n');
    final stringOffset = strings.length;
    strings.add(message);
    mov(0, 1); // stdout
    addresses.add((
      instruction: instructions.length,
      stringOffset: stringOffset,
    ));
    instructions.add(0); // adrp x1, string's 4 KiB address page
    instructions.add(0); // add x1, x1, string's offset in that page
    mov(2, message.length); // byte count, not Dart's UTF-16 string length
    mov(16, 4); // Darwin write
    instructions.add(0xd4001001); // svc #0x80
  }
  mov(0, 0); // exit status
  mov(16, 1); // Darwin exit
  instructions.add(0xd4001001);

  final codeSize = instructions.length * 4;
  final stringBytes = strings.takeBytes();
  final stringStart = codeOffset + codeSize;
  for (final address in addresses) {
    final pc = base + codeOffset + address.instruction * 4;
    final target = base + stringStart + address.stringOffset;
    final pages = (target >> 12) - (pc >> 12);
    if (pages < -(1 << 20) || pages >= 1 << 20) {
      throw UnsupportedError('String address exceeds ARM64 ADRP range');
    }
    final immediate = pages & 0x1fffff;
    instructions[address.instruction] =
        0x90000001 | ((immediate & 3) << 29) | ((immediate >> 2) << 5);
    instructions[address.instruction + 1] =
        0x91000021 | ((target & 0xfff) << 10);
  }

  final payloadEnd = stringStart + stringBytes.length;
  final textSize = (payloadEnd + pageSize - 1) & ~(pageSize - 1);
  final bytes = Uint8List(textSize + 16);
  final data = ByteData.sublistView(bytes);
  var offset = 0;

  void u32(int value) {
    data.setUint32(offset, value, Endian.little);
    offset += 4;
  }

  void u64(int value) {
    data.setUint64(offset, value, Endian.little);
    offset += 8;
  }

  void name(String value, int size) {
    bytes.setRange(offset, offset + value.length, ascii.encode(value));
    offset += size;
  }

  void segment(
    String segmentName,
    int address,
    int memorySize,
    int fileOffset,
    int fileSize,
    int protection,
    int sections,
  ) {
    u32(0x19); // LC_SEGMENT_64
    u32(72 + 80 * sections);
    name(segmentName, 16);
    u64(address);
    u64(memorySize);
    u64(fileOffset);
    u64(fileSize);
    u32(protection);
    u32(protection);
    u32(sections);
    u32(0);
  }

  void section(
    String sectionName,
    int fileOffset,
    int size,
    int alignment,
    int flags,
  ) {
    name(sectionName, 16);
    name('__TEXT', 16);
    u64(base + fileOffset);
    u64(size);
    for (final value in [fileOffset, alignment, 0, 0, flags, 0, 0, 0]) {
      u32(value);
    }
  }

  // 64-bit ARM Mach-O executable, position-independent, two-level namespace.
  for (final value in [0xfeedfacf, 0x100000c, 0, 2, 11, 0, 0x200085, 0]) {
    u32(value);
  }
  segment('__PAGEZERO', 0, base, 0, 0, 0, 0);
  segment('__TEXT', base, textSize, 0, textSize, 5, 2);
  section('__text', codeOffset, codeSize, 2, 0x80000400);
  section('__const', stringStart, stringBytes.length, 0, 0);
  segment('__LINKEDIT', base + textSize, pageSize, textSize, 16, 1, 0);

  // The system dynamic loader and system library are required on macOS ARM64.
  u32(0xe); // LC_LOAD_DYLINKER
  u32(32);
  u32(12);
  name('/usr/lib/dyld', 20);
  const systemLibrary = '/usr/lib/libSystem.B.dylib';
  final libraryCommandSize = (24 + systemLibrary.length + 1 + 7) & ~7;
  for (final value in [0xc, libraryCommandSize, 24, 0, 0x10000, 0x10000]) {
    u32(value);
  }
  name(systemLibrary, libraryCommandSize - 24);

  // LC_BUILD_VERSION: macOS, minimum 11.0, SDK 26.0.
  for (final value in [0x32, 24, 1, 0xb0000, 0x1a0000, 0]) {
    u32(value);
  }

  u32(0x1b); // LC_UUID
  u32(24);
  final random = Random.secure();
  final uuid = List<int>.generate(16, (_) => random.nextInt(256));
  uuid[6] = (uuid[6] & 0x0f) | 0x40;
  uuid[8] = (uuid[8] & 0x3f) | 0x80;
  bytes.setRange(offset, offset + 16, uuid);
  offset += 16;

  u32(0x80000028); // LC_MAIN
  u32(24);
  u64(codeOffset);
  u64(0);

  // No imported symbols, relocations, bindings, or exports.
  for (final value in [0x2, 24, textSize, 0, textSize, 1]) {
    u32(value);
  }
  u32(0xb); // LC_DYSYMTAB
  u32(80);
  offset += 72;
  u32(0x80000022); // LC_DYLD_INFO_ONLY
  u32(48);
  offset += 40;

  // codesign adds LC_CODE_SIGNATURE in the free space before the instructions.
  data.setUint32(20, offset - 32, Endian.little);
  if (offset + 16 > codeOffset) throw StateError('Load commands overlap code');
  offset = codeOffset;
  for (final instruction in instructions) {
    u32(instruction);
  }
  bytes.setRange(stringStart, payloadEnd, stringBytes);
  return (bytes: bytes, codeSize: codeSize, stringSize: stringBytes.length);
}
