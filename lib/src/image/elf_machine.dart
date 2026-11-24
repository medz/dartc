import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/native.dart';

import 'imports.dart';

/// What ELF files have of a kind of processor.
final class const ElfMachine._({
  required final int number,

  /// The program that loads programs.
  required final String interpreter,
  required final int pageBytes,

  /// The relocations of import slots, and of addresses in the file itself.
  required final int slotRelocation,
  required final int baseRelocation,

  /// Those of object files.
  required final Map<RelocationKind, int> relocations,
  required final int absoluteRelocation,
  required final int distanceRelocation,

  /// What is added to the addresses that instructions refer to.
  required final int addend,

  /// Code going to a function, where that is in it, and how.
  required final List<int> jump,
  required final int jumpOffset,
  required final int jumpRelocation,
  required final int stubBytes,
  required final Uint8List Function(List<String> names, int address, int slots)
  stubs,
}) {
  factory of(Architecture architecture) => switch (architecture) {
    .arm64 => arm64,
    .x64 => x64,
  };

  static const arm64 = ElfMachine._(
    number: 183,
    interpreter: '/lib/ld-linux-aarch64.so.1',
    pageBytes: 0x10000,
    slotRelocation: 1025,
    baseRelocation: 1027,
    relocations: {.call26: 283, .page21: 275, .pageOffset12: 277},
    absoluteRelocation: 257,
    distanceRelocation: 261,
    addend: 0,
    jump: [0, 0, 0, 0x14],
    jumpOffset: 0,
    jumpRelocation: 282,
    stubBytes: arm64StubBytes,
    stubs: arm64Stubs,
  );

  static const x64 = ElfMachine._(
    number: 62,
    interpreter: '/lib64/ld-linux-x86-64.so.2',
    pageBytes: 0x1000,
    slotRelocation: 6,
    baseRelocation: 8,
    relocations: {.call32: 4, .relative32: 2},
    absoluteRelocation: 1,
    distanceRelocation: 2,
    addend: -4,
    jump: [0xe9, 0, 0, 0, 0],
    jumpOffset: 1,
    jumpRelocation: 4,
    stubBytes: x64StubBytes,
    stubs: x64Stubs,
  );
}
