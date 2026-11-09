import 'dart:typed_data';

import 'package:dartc/target.dart';

/// An instruction field whose destination is not yet known.
///
/// [offset] is measured from code start, at the AArch64 instruction or the
/// x86-64 displacement field. [encoding] owns its PC base and range checks.
final class const Fixup(final int offset, final FixupEncoding encoding);

/// The encoding and validation rules for a PC-relative instruction field.
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
  x64Call32(.x64, 0xe8, 0xff, 32, 0),
  x64Jump32(.x64, 0xe9, 0xff, 32, 0),
  x64Conditional32(.x64, 0x800f, 0xf0ff, 32, 0);

  int get _fieldMask => ((1 << _bits) - 1) << _shift;

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
      final prefix = this == .x64Conditional32 ? 2 : 1;
      if (offset < prefix) throw ArgumentError('Missing instruction prefix.');
      opcode = prefix == 2
          ? code.getUint16(offset - 2, .little)
          : code.getUint8(offset - 1);
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
    final displacement = targetAddress + addend - placeAddress - (arm ? 0 : 4);
    final scale = arm ? 4 : 1, limit = (1 << (_bits - 1)) * scale;
    RangeError.checkValueInInterval(
      displacement,
      -limit,
      limit - scale,
      'displacement',
    );
    if (arm && (placeAddress % 4 != 0 || displacement % 4 != 0)) {
      throw ArgumentError('Expected aligned instruction and target addresses.');
    }
    final field = ((displacement ~/ scale) << _shift) & _fieldMask;
    code.setUint32(
      offset,
      (code.getUint32(offset, .little) & ~_fieldMask) | field,
      .little,
    );
  }
}
