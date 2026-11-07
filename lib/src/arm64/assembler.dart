import 'dart:typed_data';

/// A 64-bit general-purpose register; SP and XZR have separate encodings.
enum Register() {
  x0,
  x1,
  x2,
  x3,
  x4,
  x5,
  x6,
  x7,
  x8,
  x9,
  x10,
  x11,
  x12,
  x13,
  x14,
  x15,
  x16,
  x17,
  x18,
  x19,
  x20,
  x21,
  x22,
  x23,
  x24,
  x25,
  x26,
  x27,
  x28,
  x29,
  x30,
}

/// Encodes AArch64 integer instructions in little-endian order.
final class Assembler() {
  final _bytes = BytesBuilder(copy: false);

  /// Moves a register without changing condition flags.
  void move(Register destination, Register source) {
    if (destination != source) {
      _word(0xaa0003e0 | source.index << 16 | destination.index);
    }
  }

  /// Loads all 64 bits of [value] without reading a literal pool.
  void loadImmediate(Register destination, int value) {
    _word(0xd2800000 | (value & 0xffff) << 5 | destination.index);
    for (var part = 1; part < 4; part++) {
      final bits = (value >>> (16 * part)) & 0xffff;
      if (bits != 0) {
        _word(0xf2800000 | part << 21 | bits << 5 | destination.index);
      }
    }
  }

  /// Adds two registers, wrapping at 64 bits without changing condition flags.
  void add(Register destination, Register left, Register right) => _word(
    0x8b000000 | right.index << 16 | left.index << 5 | destination.index,
  );

  /// Subtracts [right] from [left], wrapping at 64 bits.
  void subtract(Register destination, Register left, Register right) => _word(
    0xcb000000 | right.index << 16 | left.index << 5 | destination.index,
  );

  /// Returns through the address in [address].
  void ret([Register address = .x30]) => _word(0xd65f0000 | address.index << 5);

  /// Returns the encoded bytes and resets the buffer.
  Uint8List takeBytes() => _bytes.takeBytes();

  void _word(int word) => _bytes.add([
    word & 255,
    (word >>> 8) & 255,
    (word >>> 16) & 255,
    word >>> 24,
  ]);
}
