import 'dart:typed_data';

/// A 64-bit general-purpose register or the stack pointer.
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
  sp,
}

/// Encodes AArch64 integer instructions in little-endian order.
final class Assembler() {
  final _bytes = BytesBuilder(copy: false);

  /// The number of encoded bytes.
  int get length => _bytes.length;

  /// Moves a register without changing condition flags.
  void move(Register destination, Register source) {
    if (destination == .sp || source == .sp) {
      addImmediate(destination, source, 0);
    } else if (destination != source) {
      _word(0xaa0003e0 | source.index << 16 | destination.index);
    }
  }

  /// Loads all 64 bits of [value] without reading a literal pool.
  void loadImmediate(Register destination, int value) {
    _general(destination);
    _word(0xd2800000 | (value & 0xffff) << 5 | destination.index);
    for (var part = 1; part < 4; part++) {
      final bits = (value >>> (16 * part)) & 0xffff;
      if (bits != 0) {
        _word(0xf2800000 | part << 21 | bits << 5 | destination.index);
      }
    }
  }

  /// Adds two registers, wrapping at 64 bits without changing condition flags.
  void add(Register destination, Register left, Register right) {
    _general(destination);
    _general(left);
    _general(right);
    _word(0x8b000000 | right.index << 16 | left.index << 5 | destination.index);
  }

  /// Subtracts [right] from [left], wrapping at 64 bits.
  void subtract(Register destination, Register left, Register right) {
    _general(destination);
    _general(left);
    _general(right);
    _word(0xcb000000 | right.index << 16 | left.index << 5 | destination.index);
  }

  /// Adds a signed 24-bit magnitude, including to or from SP, preserving flags.
  void addImmediate(Register destination, Register source, int value) {
    RangeError.checkValueInInterval(value, -0xffffff, 0xffffff, 'value');
    final magnitude = value.abs(), opcode = value < 0 ? 0xd1000000 : 0x91000000;
    if (magnitude > 4095) {
      _word(
        opcode |
            1 << 22 |
            (magnitude >> 12) << 10 |
            source.index << 5 |
            destination.index,
      );
      if (magnitude & 4095 == 0) return;
      source = destination;
    }
    _word(
      opcode | (magnitude & 4095) << 10 | source.index << 5 | destination.index,
    );
  }

  /// Loads a word at an unsigned, eight-byte-aligned offset from [base].
  void load(Register destination, Register base, int offset) =>
      _memory(0xf9400000, destination, base, offset);

  /// Stores a word with the same address constraints as [load].
  void store(Register source, Register base, int offset) =>
      _memory(0xf9000000, source, base, offset);

  /// Calls a PC-relative target and places the return address in X30.
  void call(int displacement) => _word(_callWord(displacement));

  void _memory(int opcode, Register value, Register base, int offset) {
    _general(value);
    RangeError.checkValueInInterval(offset, 0, 32760, 'offset');
    if (offset % 8 != 0) throw ArgumentError('Expected an eight-byte offset.');
    _word(opcode | (offset ~/ 8) << 10 | base.index << 5 | value.index);
  }

  void _general(Register register) {
    if (register == .sp) {
      throw ArgumentError('SP is not valid for this instruction.');
    }
  }

  /// Returns through the address in [address].
  void ret([Register address = .x30]) {
    _general(address);
    _word(0xd65f0000 | address.index << 5);
  }

  /// Returns the encoded bytes and resets the buffer.
  Uint8List takeBytes() => _bytes.takeBytes();

  void _word(int word) => _bytes.add([
    word & 255,
    (word >>> 8) & 255,
    (word >>> 16) & 255,
    word >>> 24,
  ]);
}

/// Patches AArch64 branch instructions in a writable code buffer.
extension Arm64CallPatch on ByteData {
  /// Replaces a BL displacement measured from the instruction address.
  void patchArm64Call(int offset, int displacement) {
    if (offset % 4 != 0 ||
        getUint32(offset, .little) & 0xfc000000 != 0x94000000) {
      throw ArgumentError('Expected an aligned BL instruction.');
    }
    setUint32(offset, _callWord(displacement), .little);
  }
}

int _callWord(int displacement) {
  RangeError.checkValueInInterval(
    displacement,
    -0x8000000,
    0x7fffffc,
    'displacement',
  );
  if (displacement % 4 != 0) {
    throw ArgumentError('Expected an aligned call target.');
  }
  return 0x94000000 | (displacement >> 2) & 0x3ffffff;
}
