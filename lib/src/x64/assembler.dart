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

/// A condition on the flags produced by a signed integer comparison.
enum Condition(final int encoding) {
  equal(4),
  notEqual(5),
  lessThan(12),
  lessOrEqual(14),
  greaterThan(15),
  greaterOrEqual(13),
}

/// Encodes x86-64 integer instructions.
final class Assembler() {
  final _bytes = BytesBuilder(copy: false);

  /// The number of encoded bytes.
  int get length => _bytes.length;

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

  /// Adds a signed 32-bit immediate to a register, updating flags.
  void addImmediate(Register destination, int value) {
    RangeError.checkValueInInterval(value, -0x80000000, 0x7fffffff, 'value');
    final bytes = ByteData(7)
      ..setUint8(0, 0x48 | destination.index >> 3)
      ..setUint8(1, 0x81)
      ..setUint8(2, 0xc0 | destination.index & 7)
      ..setInt32(3, value, .little);
    _bytes.add(bytes.buffer.asUint8List());
  }

  /// Pushes a 64-bit register onto the stack.
  void push(Register value) {
    if (value.index >= 8) _bytes.addByte(0x41);
    _bytes.addByte(0x50 | value.index & 7);
  }

  /// Pops a 64-bit register from the stack.
  void pop(Register destination) {
    if (destination.index >= 8) _bytes.addByte(0x41);
    _bytes.addByte(0x58 | destination.index & 7);
  }

  /// Loads a word from RSP plus a signed 32-bit displacement.
  void loadStack(Register destination, int offset) =>
      _stack(0x8b, destination, offset);

  /// Stores a word at RSP plus a signed 32-bit displacement.
  void storeStack(Register source, int offset) => _stack(0x89, source, offset);

  /// Updates flags as if subtracting [right] from [left], preserving registers.
  void compare(Register left, Register right) => _binary(0x39, left, right);

  /// Writes 0 or 1 for [condition], preserving flags and other registers.
  void setCondition(Register destination, Condition condition) {
    final low = destination.index & 7, high = destination.index >> 3;
    _bytes.add([
      0x40 | high,
      0x0f,
      0x90 | condition.encoding,
      0xc0 | low,
      0x48 | high << 2 | high,
      0x0f,
      0xb6,
      0xc0 | low << 3 | low,
    ]);
  }

  /// Jumps relative to the end of this instruction, preserving registers and flags.
  void jump(int displacement) {
    _checkDisplacement(displacement);
    final bytes = ByteData(5)
      ..setUint8(0, 0xe9)
      ..setInt32(1, displacement, .little);
    _bytes.add(bytes.buffer.asUint8List());
  }

  /// Jumps when flags match [condition], relative to the end of this instruction.
  void jumpCondition(Condition condition, int displacement) {
    _checkDisplacement(displacement);
    final bytes = ByteData(6)
      ..setUint8(0, 0x0f)
      ..setUint8(1, 0x80 | condition.encoding)
      ..setInt32(2, displacement, .little);
    _bytes.add(bytes.buffer.asUint8List());
  }

  /// Updates flags by testing [value] against zero, preserving all registers.
  void test(Register value) => _binary(0x85, value, value);

  /// Calls a target relative to the end of this instruction.
  void call(int displacement) {
    _checkDisplacement(displacement);
    final bytes = ByteData(5)
      ..setUint8(0, 0xe8)
      ..setInt32(1, displacement, .little);
    _bytes.add(bytes.buffer.asUint8List());
  }

  void _stack(int opcode, Register value, int offset) {
    RangeError.checkValueInInterval(offset, -0x80000000, 0x7fffffff, 'offset');
    final bytes = ByteData(8)
      ..setUint8(0, 0x48 | (value.index >> 3) << 2)
      ..setUint8(1, opcode)
      ..setUint8(2, 0x84 | (value.index & 7) << 3)
      ..setUint8(3, 0x24)
      ..setInt32(4, offset, .little);
    _bytes.add(bytes.buffer.asUint8List());
  }

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

/// Patches x86-64 relative branches in a writable code buffer.
extension X64BranchPatch on ByteData {
  /// Replaces a JMP or near Jcc displacement measured from the field's end.
  void patchX64Branch(int offset, int displacement) {
    final jump = offset > 0 && getUint8(offset - 1) == 0xe9;
    final conditional =
        offset > 1 &&
        getUint8(offset - 2) == 0x0f &&
        getUint8(offset - 1) & 0xf0 == 0x80;
    if (!jump && !conditional) {
      throw ArgumentError('Expected a JMP or Jcc field.');
    }
    _checkDisplacement(displacement);
    setInt32(offset, displacement, .little);
  }

  /// Replaces a displacement measured from the end of the four-byte field.
  void patchX64Call(int offset, int displacement) {
    if (offset <= 0 || getUint8(offset - 1) != 0xe8) {
      throw ArgumentError('Expected a CALL displacement field.');
    }
    _checkDisplacement(displacement);
    setInt32(offset, displacement, .little);
  }
}

void _checkDisplacement(int displacement) => RangeError.checkValueInInterval(
  displacement,
  -0x80000000,
  0x7fffffff,
  'displacement',
);
