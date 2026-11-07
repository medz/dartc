import 'dart:typed_data';

/// A general-purpose register in instruction encoding order.
enum Register() {
  rax,
  rcx,
  rdx,
  rbx,
  rsp,
  rbp,
  rsi,
  rdi,
  r8,
  r9,
  r10,
  r11,
  r12,
  r13,
  r14,
  r15,
}

/// Encodes x86-64 integer instructions.
final class Assembler() {
  final _bytes = BytesBuilder(copy: false);

  /// Copies all 64 bits of [source].
  void move(Register destination, Register source) {
    if (destination != source) _binary(0x89, destination, source);
  }

  /// Loads all 64 bits of [value].
  void loadImmediate(Register destination, int value) {
    final bytes = ByteData(10)
      ..setUint8(0, 0x48 | destination.index >> 3)
      ..setUint8(1, 0xb8 | destination.index & 7)
      ..setInt64(2, value, Endian.little);
    _bytes.add(bytes.buffer.asUint8List());
  }

  /// Adds [source] to [destination], wrapping at 64 bits and updating flags.
  void add(Register destination, Register source) =>
      _binary(0x01, destination, source);

  /// Subtracts [source] from [destination], wrapping at 64 bits and updating flags.
  void subtract(Register destination, Register source) =>
      _binary(0x29, destination, source);

  /// Negates [value], wrapping at 64 bits and updating flags.
  void negate(Register value) =>
      _bytes.add([0x48 | value.index >> 3, 0xf7, 0xd8 | value.index & 7]);

  /// Returns through the address at the top of the stack.
  void ret() => _bytes.addByte(0xc3);

  /// Returns the encoded bytes and resets the buffer.
  Uint8List takeBytes() => _bytes.takeBytes();

  void _binary(int opcode, Register destination, Register source) =>
      _bytes.add([
        0x48 | (source.index >> 3) << 2 | destination.index >> 3,
        opcode,
        0xc0 | (source.index & 7) << 3 | destination.index & 7,
      ]);
}
