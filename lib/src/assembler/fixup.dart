import 'dart:typed_data';

import 'package:dartc/target.dart';

/// An instruction field whose destination is not yet known.
///
/// [offset] is measured from code start, at the AArch64 instruction or the
/// x86-64 displacement field. [encoding] owns its PC base and range checks.
final class const Fixup(final int offset, final FixupEncoding encoding);

/// The encoding and validation rules for branch and address instruction fields.
enum FixupEncoding(
  final Architecture architecture,
  final int _opcode,
  final int _opcodeMask,
  final int _bits,
  final int _shift,
) {
  arm64Call26(.arm64, 0x94000000, 0xfc000000, 26, 0),
  arm64Branch26(.arm64, 0x14000000, 0xfc000000, 26, 0),
  arm64Zero19(.arm64, 0xb4000000, 0xff000000, 19, 5),
  arm64Page21(.arm64, 0x90000000, 0x9f000000, 21, 0),
  arm64PageOffset12(.arm64, 0x91000000, 0xffc00000, 12, 10),
  arm64LoadPageOffset12(.arm64, 0xf9400000, 0xffc00000, 12, 10),
  x64Call32(.x64, 0xe8, 0xff, 32, 0),
  x64Jump32(.x64, 0xe9, 0xff, 32, 0),
  x64Conditional32(.x64, 0x800f, 0xf0ff, 32, 0),
  x64Address32(.x64, 0x058d48, 0xc7fffb, 32, 0),
  x64LoadAddress32(.x64, 0x058b48, 0xc7fffb, 32, 0);

  int get _fieldMask =>
      this == .arm64Page21 ? 0x60ffffe0 : ((1 << _bits) - 1) << _shift;

  /// Checks the instruction, field bounds and alignment before it is patched.
  ///
  /// If [unresolved] is true, the displacement must still be zero.
  void validate(ByteData code, int offset, {bool unresolved = false}) {
    RangeError.checkValueInInterval(
      offset,
      0,
      code.lengthInBytes - 4,
      'offset',
    );
    final int opcode;
    if (architecture == .arm64) {
      if (offset % 4 != 0) {
        throw ArgumentError('Expected an aligned instruction.');
      }
      opcode = code.getUint32(offset, .little);
    } else {
      final prefix = this == .x64Address32 || this == .x64LoadAddress32
          ? 3
          : this == .x64Conditional32
          ? 2
          : 1;
      if (offset < prefix) throw ArgumentError('Missing instruction prefix.');
      opcode = switch (prefix) {
        3 =>
          code.getUint8(offset - 3) | code.getUint16(offset - 2, .little) << 8,
        2 => code.getUint16(offset - 2, .little),
        _ => code.getUint8(offset - 1),
      };
    }
    if (opcode & _opcodeMask != _opcode ||
        unresolved && code.getUint32(offset, .little) & _fieldMask != 0) {
      throw ArgumentError('Invalid $name field at $offset.');
    }
  }

  /// Patches a destination address without changing other instruction bits.
  ///
  /// [placeAddress] is the address of the field at [offset]. The target address
  /// includes [addend]. Invalid instructions or displacements leave [code]
  /// unchanged.
  void apply(
    ByteData code,
    int offset, {
    required int placeAddress,
    required int targetAddress,
    int addend = 0,
  }) {
    validate(code, offset);
    final arm = architecture == .arm64;
    if (arm && placeAddress % 4 != 0) {
      throw ArgumentError('Expected an aligned instruction address.');
    }
    final destination = targetAddress + addend;
    final int field;
    if (this == .arm64PageOffset12) {
      field = (destination & 0xfff) << 10;
    } else if (this == .arm64LoadPageOffset12) {
      if (destination % 8 != 0) {
        throw ArgumentError('Expected an eight-byte aligned load address.');
      }
      field = ((destination & 0xfff) >> 3) << 10;
    } else if (this == .arm64Page21) {
      final pages = (destination >> 12) - (placeAddress >> 12);
      RangeError.checkValueInInterval(pages, -0x100000, 0xfffff, 'pages');
      field = (pages & 3) << 29 | ((pages >> 2) & 0x7ffff) << 5;
    } else {
      final displacement = destination - placeAddress - (arm ? 0 : 4);
      final scale = arm ? 4 : 1, limit = (1 << (_bits - 1)) * scale;
      RangeError.checkValueInInterval(
        displacement,
        -limit,
        limit - scale,
        'displacement',
      );
      if (arm && displacement % 4 != 0) {
        throw ArgumentError('Expected an aligned target address.');
      }
      field = ((displacement ~/ scale) << _shift) & _fieldMask;
    }
    code.setUint32(
      offset,
      (code.getUint32(offset, .little) & ~_fieldMask) | field,
      .little,
    );
  }
}
