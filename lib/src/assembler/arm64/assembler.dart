import 'dart:typed_data';

import '../code_buffer.dart';
import '../fixup.dart';
import 'registers.dart';

/// Encodes AArch64 scalar instructions in little-endian order.
final class Assembler() {
  final _bytes = CodeBuffer();

  /// The number of bytes in this open assembler.
  int get length => _bytes.length;

  /// Moves a register without changing condition flags.
  void move(Register destination, Register source) {
    _bytes.checkOpen();
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

  /// Adds [left] to [right] shifted left by [shift], without changing flags.
  ///
  /// [shift] must be 0–63. The result wraps at 64 bits.
  void add(
    Register destination,
    Register left,
    Register right, {
    int shift = 0,
  }) {
    RangeError.checkValueInInterval(shift, 0, 63, 'shift');
    _binary(0x8b000000 | shift << 10, destination, left, right);
  }

  /// Subtracts [right] from [left], wrapping at 64 bits.
  void subtract(Register destination, Register left, Register right) =>
      _binary(0xcb000000, destination, left, right);

  /// Multiplies two registers, wrapping at 64 bits without changing flags.
  void multiply(Register destination, Register left, Register right) =>
      _binary(0x9b007c00, destination, left, right);

  /// Computes a 64-bit bitwise conjunction without changing flags.
  void bitAnd(Register destination, Register left, Register right) =>
      _binary(0x8a000000, destination, left, right);

  /// Computes a 64-bit bitwise disjunction without changing flags.
  void bitOr(Register destination, Register left, Register right) =>
      _binary(0xaa000000, destination, left, right);

  /// Computes a 64-bit bitwise exclusive or without changing flags.
  void bitXor(Register destination, Register left, Register right) =>
      _binary(0xca000000, destination, left, right);

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

  /// Loads 1, 2, 4 or 8 bytes, extending the value into a 64-bit register.
  ///
  /// [offset] is unsigned, aligned to [bytes] and at most `4095 * bytes`.
  void load(
    Register destination,
    Register base,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) {
    final size = _size(bytes);
    _memory(
      (size << 30) | (signed && bytes < 8 ? 0x39800000 : 0x39400000),
      destination,
      base,
      offset,
      bytes,
    );
  }

  /// Stores the low [bytes] with the same address constraints as [load].
  void store(Register source, Register base, int offset, {int bytes = 8}) =>
      _memory((_size(bytes) << 30) | 0x39000000, source, base, offset, bytes);

  /// Extends the low 1, 2, 4 or 8 bytes without changing flags.
  void extendInteger(
    Register destination,
    Register source, {
    required int bytes,
    required bool signed,
  }) {
    _size(bytes);
    _general(destination);
    _general(source);
    if (bytes == 8) {
      move(destination, source);
    } else {
      _word(
        (signed ? 0x93400000 : 0xd3400000) |
            (bytes * 8 - 1) << 10 |
            source.index << 5 |
            destination.index,
      );
    }
  }

  /// Sets NZCV as if subtracting [right] from [left], without storing a result.
  void compare(Register left, Register right) {
    _general(left);
    _general(right);
    _word(0xeb00001f | right.index << 16 | left.index << 5);
  }

  /// Copies a double's bits without changing flags.
  void moveDouble(FloatRegister destination, FloatRegister source) {
    _bytes.checkOpen();
    if (destination != source) _float(0x1e604000, destination, source);
  }

  /// Copies raw bits from a general register into a double register.
  void moveBitsToDouble(FloatRegister destination, Register source) {
    _general(source);
    _word(0x9e670000 | source.index << 5 | destination.index);
  }

  /// Copies raw bits from a double register into a general register.
  void moveBitsToGeneral(Register destination, FloatRegister source) {
    _general(destination);
    _word(0x9e660000 | source.index << 5 | destination.index);
  }

  /// Converts a signed 64-bit integer using the current FPCR rounding mode.
  void convertIntToDouble(FloatRegister destination, Register source) {
    _general(source);
    _word(0x9e620000 | source.index << 5 | destination.index);
  }

  /// Truncates toward zero; out-of-range values saturate and NaN becomes zero.
  void truncateDoubleToInt(Register destination, FloatRegister source) {
    _general(destination);
    _word(0x9e780000 | source.index << 5 | destination.index);
  }

  /// Converts the low 32-bit float to a double, changing only [destination].
  void convertFloatToDouble(FloatRegister destination, FloatRegister source) =>
      _float(0x1e22c000, destination, source);

  /// Rounds a double to the low 32 bits using the current FPCR rounding mode.
  void convertDoubleToFloat(FloatRegister destination, FloatRegister source) =>
      _float(0x1e624000, destination, source);

  /// Adds two IEEE 754 doubles.
  void addDouble(
    FloatRegister destination,
    FloatRegister left,
    FloatRegister right,
  ) => _float(0x1e602800, destination, left, right);

  /// Subtracts two IEEE 754 doubles.
  void subtractDouble(
    FloatRegister destination,
    FloatRegister left,
    FloatRegister right,
  ) => _float(0x1e603800, destination, left, right);

  /// Multiplies two IEEE 754 doubles without fusion with another operation.
  void multiplyDouble(
    FloatRegister destination,
    FloatRegister left,
    FloatRegister right,
  ) => _float(0x1e600800, destination, left, right);

  /// Divides two IEEE 754 doubles.
  void divideDouble(
    FloatRegister destination,
    FloatRegister left,
    FloatRegister right,
  ) => _float(0x1e601800, destination, left, right);

  /// Flips the sign bit without changing NaN payloads or flags.
  void negateDouble(FloatRegister destination, FloatRegister source) =>
      _float(0x1e614000, destination, source);

  /// Sets NZCV for FCMP, including unordered comparisons when an operand is NaN.
  void compareDouble(FloatRegister left, FloatRegister right) =>
      _word(0x1e602000 | right.index << 16 | left.index << 5);

  /// Loads a double with the address constraints of [load].
  void loadDouble(FloatRegister destination, Register base, int offset) =>
      _memory(0xfd400000, destination, base, offset);

  /// Stores a double with the address constraints of [store].
  void storeDouble(FloatRegister source, Register base, int offset) =>
      _memory(0xfd000000, source, base, offset);

  /// Loads 32 float bits; [offset] is a nonnegative multiple of four below 16384.
  void loadFloat(FloatRegister destination, Register base, int offset) =>
      _memory(0xbd400000, destination, base, offset, 4);

  /// Stores the low 32 bits with the address constraints of [loadFloat].
  void storeFloat(FloatRegister source, Register base, int offset) =>
      _memory(0xbd000000, source, base, offset, 4);

  void _float(
    int opcode,
    FloatRegister destination,
    FloatRegister left, [
    FloatRegister? right,
  ]) => _word(
    opcode | (right?.index ?? 0) << 16 | left.index << 5 | destination.index,
  );

  /// Writes 0 or 1 for [condition], preserving NZCV and other registers.
  void setCondition(Register destination, Condition condition) {
    _general(destination);
    _word(0x9a9f07e0 | (condition.encoding ^ 1) << 12 | destination.index);
  }

  /// Creates a local branch destination for this assembler.
  Label label() => _bytes.label();

  /// Binds a local label to the next instruction.
  void bind(Label label) => _bytes.bind(label);

  /// Branches to a local label, preserving registers and flags.
  void branch(Label target) {
    _bytes.branch(Fixup(length, .arm64Branch26), target);
    _word(0x14000000);
  }

  /// Branches to a local label when [value] is zero, preserving flags.
  void branchZero(Register value, Label target) {
    _general(value);
    _bytes.branch(Fixup(length, .arm64Zero19), target);
    _word(0xb4000000 | value.index);
  }

  /// Emits an unresolved call that places the return address in X30.
  Fixup call() {
    final fixup = Fixup(length, .arm64Call26);
    _word(0x94000000);
    return fixup;
  }

  /// Calls the address in [target], placing the return address in X30.
  void callRegister(Register target) {
    _general(target);
    _word(0xd63f0000 | target.index << 5);
  }

  /// Branches to the address in [target] without changing X30 or flags.
  void branchRegister(Register target) {
    _general(target);
    _word(0xd61f0000 | target.index << 5);
  }

  /// Loads the 4 KiB page of an unresolved address, preserving flags.
  Fixup pageAddress(Register destination) {
    _general(destination);
    final fixup = Fixup(length, .arm64Page21);
    _word(0x90000000 | destination.index);
    return fixup;
  }

  /// Adds an unresolved address's low 12 bits to [source], preserving flags.
  Fixup addPageOffset(Register destination, Register source) {
    final fixup = Fixup(length, .arm64PageOffset12);
    _word(0x91000000 | source.index << 5 | destination.index);
    return fixup;
  }

  /// Loads eight bytes at [base] plus an unresolved address's low 12 bits.
  ///
  /// The resolved address must be eight-byte aligned.
  Fixup loadPageOffset(Register destination, Register base) {
    _general(destination);
    final fixup = Fixup(length, .arm64LoadPageOffset12);
    _word(0xf9400000 | base.index << 5 | destination.index);
    return fixup;
  }

  int _size(int bytes) => switch (bytes) {
    1 => 0,
    2 => 1,
    4 => 2,
    8 => 3,
    _ => throw ArgumentError.value(bytes, 'bytes', 'Expected 1, 2, 4 or 8.'),
  };

  void _memory(
    int opcode,
    CpuRegister value,
    Register base,
    int offset, [
    int bytes = 8,
  ]) {
    if (value is Register) _general(value);
    RangeError.checkValueInInterval(offset, 0, 4095 * bytes, 'offset');
    if (offset % bytes != 0) throw ArgumentError('Expected an aligned offset.');
    _word(opcode | (offset ~/ bytes) << 10 | base.index << 5 | value.index);
  }

  void _binary(
    int opcode,
    Register destination,
    Register left,
    Register right,
  ) {
    _general(destination);
    _general(left);
    _general(right);
    _word(opcode | right.index << 16 | left.index << 5 | destination.index);
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

  /// Resolves local branches and returns immutable machine code.
  ///
  /// Closes this assembler even if an unbound or out-of-range label prevents
  /// completion. Further emission, label changes and completion are rejected.
  Uint8List finish() => _bytes.finish();

  void _word(int word) => _bytes.add([
    word & 255,
    (word >>> 8) & 255,
    (word >>> 16) & 255,
    word >>> 24,
  ]);
}
