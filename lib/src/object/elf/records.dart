import 'dart:typed_data';

import 'package:dartc/target.dart';

import '../section.dart';
import '../symbol.dart';

/// The ELF symbol type associated with a known or unspecified definition.
extension ElfSymbolKind on SymbolKind {
  /// The STT_NOTYPE, STT_FUNC or STT_OBJECT value.
  int get elfType => switch (this) {
    .unknown => 0,
    .function => 2,
    .data => 1,
  };
}

/// ELF names, storage types and allocation permissions for supported sections.
extension ElfSectionKind on SectionKind {
  /// The ELF section name.
  String get elfName => switch (this) {
    .code => '.text',
    .readOnlyData => '.rodata',
    .data => '.data',
    .zeroFill => '.bss',
  };

  /// The SHT_PROGBITS or SHT_NOBITS storage type.
  int get elfType => this == .zeroFill ? 8 : 1;

  /// The allocation, write and execute flags.
  int get elfFlags => switch (this) {
    .code => 6,
    .readOnlyData => 2,
    .data || .zeroFill => 3,
  };
}

/// Writes little-endian ELF64 file records into a caller-owned buffer.
extension ElfRecords on ByteData {
  /// Writes the file header, including its reserved zero bytes.
  ///
  /// [type] is the ELF file type. Program headers, when present, start at byte
  /// 64. Section numbering uses the ordinary 16-bit header fields.
  /// [entryAddress] is the virtual entry address, or zero for files without one.
  void writeElf64Header({
    required Architecture architecture,
    required int type,
    required int sectionOffset,
    required int sectionCount,
    required int sectionNames,
    int programCount = 0,
    int entryAddress = 0,
  }) {
    RangeError.checkValidRange(0, 64, lengthInBytes);
    for (final value in [type, sectionCount, sectionNames, programCount]) {
      RangeError.checkValueInInterval(value, 0, 0xffff);
    }
    RangeError.checkNotNegative(sectionOffset, 'sectionOffset');
    RangeError.checkNotNegative(entryAddress, 'entryAddress');
    final bytes = buffer.asUint8List(offsetInBytes, 64)..fillRange(0, 64, 0);
    bytes.setAll(0, [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
    setUint16(16, type, .little);
    setUint16(18, architecture == .arm64 ? 183 : 62, .little);
    setUint32(20, 1, .little);
    setUint64(24, entryAddress, .little);
    setUint64(32, programCount == 0 ? 0 : 64, .little);
    setUint64(40, sectionOffset, .little);
    setUint16(52, 64, .little);
    setUint16(54, programCount == 0 ? 0 : 56, .little);
    setUint16(56, programCount, .little);
    setUint16(58, 64, .little);
    setUint16(60, sectionCount, .little);
    setUint16(62, sectionNames, .little);
  }

  /// Writes one section header at [offset], preserving surrounding bytes.
  ///
  /// [name] is an offset in the section-name string table. [flags] and [address]
  /// are 64-bit bit patterns; all file offsets and sizes must be nonnegative.
  void writeElf64Section(
    int offset, {
    required int name,
    required int type,
    required int flags,
    required int fileOffset,
    required int size,
    int address = 0,
    int link = 0,
    int info = 0,
    int alignment = 1,
    int entrySize = 0,
  }) {
    RangeError.checkValueInInterval(offset, 0, lengthInBytes - 64, 'offset');
    for (final value in [name, type, link, info]) {
      RangeError.checkValueInInterval(value, 0, 0xffffffff);
    }
    for (final value in [fileOffset, size, alignment, entrySize]) {
      RangeError.checkNotNegative(value);
    }
    setUint32(offset, name, .little);
    setUint32(offset + 4, type, .little);
    setUint64(offset + 8, flags, .little);
    setUint64(offset + 16, address, .little);
    setUint64(offset + 24, fileOffset, .little);
    setUint64(offset + 32, size, .little);
    setUint32(offset + 40, link, .little);
    setUint32(offset + 44, info, .little);
    setUint64(offset + 48, alignment, .little);
    setUint64(offset + 56, entrySize, .little);
  }
}
