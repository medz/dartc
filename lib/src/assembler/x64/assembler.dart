import 'dart:typed_data';

import '../code_buffer.dart';
import '../fixup.dart';
import 'registers.dart';

/// Encodes x86-64 scalar instructions.
final class Assembler() {
  final _bytes = CodeBuffer();

  /// The number of bytes in this open assembler.
  int get length => _bytes.length;

  /// Copies all 64 bits of [source].
  void move(Register destination, Register source) {
    _bytes.checkOpen();
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

  /// Computes [base] plus [index] times [scale], preserving memory and flags.
  ///
  /// The result wraps at 64 bits. [scale] must be 1, 2, 4 or 8; [index] cannot
  /// be RSP. The destination may alias either input.
  void lea(
    Register destination,
    Register base,
    Register index, {
    int scale = 1,
  }) {
    if (scale != 1 && scale != 2 && scale != 4 && scale != 8) {
      throw ArgumentError.value(scale, 'scale', 'Expected 1, 2, 4 or 8.');
    }
    if (index == .rsp) {
      throw ArgumentError.value(index, 'index', 'RSP cannot index an address.');
    }
    final displacement = base.index & 7 == 5;
    _bytes.add([
      0x48 |
          (destination.index >> 3) << 2 |
          (index.index >> 3) << 1 |
          base.index >> 3,
      0x8d,
      (displacement ? 0x40 : 0) | (destination.index & 7) << 3 | 4,
      (scale.bitLength - 1) << 6 | (index.index & 7) << 3 | base.index & 7,
      if (displacement) 0,
    ]);
  }

  /// Subtracts [source] from [destination], wrapping at 64 bits and updating flags.
  void subtract(Register destination, Register source) =>
      _binary(0x29, destination, source);

  /// Multiplies [destination] by [source], wrapping at 64 bits and changing flags.
  void multiply(Register destination, Register source) => _bytes.add([
    0x48 | (destination.index >> 3) << 2 | source.index >> 3,
    0x0f,
    0xaf,
    0xc0 | (destination.index & 7) << 3 | source.index & 7,
  ]);

  /// Sign-extends RAX into RDX:RAX without changing flags.
  void extendDividend() => _bytes.add([0x48, 0x99]);

  /// Divides signed RDX:RAX by [divisor], producing RAX quotient and RDX remainder.
  ///
  /// Zero divisors and quotients outside signed 64-bit range trap; flags are undefined.
  void divideSigned(Register divisor) =>
      _bytes.add([0x48 | divisor.index >> 3, 0xf7, 0xf8 | divisor.index & 7]);

  /// Shifts [value] left by the low six bits of CL, changing flags.
  void shiftLeft(Register value) =>
      _bytes.add([0x48 | value.index >> 3, 0xd3, 0xe0 | value.index & 7]);

  /// Shifts [value] right with sign extension by the low six bits of CL.
  void shiftRightSigned(Register value) =>
      _bytes.add([0x48 | value.index >> 3, 0xd3, 0xf8 | value.index & 7]);

  /// Shifts [value] right with zero extension by the low six bits of CL.
  void shiftRightUnsigned(Register value) =>
      _bytes.add([0x48 | value.index >> 3, 0xd3, 0xe8 | value.index & 7]);

  /// Computes a 64-bit bitwise conjunction in [destination], updating flags.
  void bitAnd(Register destination, Register source) =>
      _binary(0x21, destination, source);

  /// Computes a 64-bit bitwise disjunction in [destination], updating flags.
  void bitOr(Register destination, Register source) =>
      _binary(0x09, destination, source);

  /// Computes a 64-bit bitwise exclusive or in [destination], updating flags.
  void bitXor(Register destination, Register source) =>
      _binary(0x31, destination, source);

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

  /// Loads 1, 2, 4 or 8 bytes, extending the value into a 64-bit register.
  ///
  /// [offset] is a signed 32-bit displacement from [base].
  void load(
    Register destination,
    Register base,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) => _memory(0x8b, destination, base, offset, bytes: bytes, signed: signed);

  /// Stores the low 1, 2, 4 or 8 bytes at [base] plus [offset].
  void store(Register source, Register base, int offset, {int bytes = 8}) =>
      _memory(0x89, source, base, offset, bytes: bytes);

  /// Extends the low 1, 2, 4 or 8 bytes without changing flags.
  void extendInteger(
    Register destination,
    Register source, {
    required int bytes,
    required bool signed,
  }) {
    _checkSize(bytes);
    if (bytes == 8) {
      move(destination, source);
      return;
    }
    _bytes.add([
      0x40 |
          (bytes < 4 || signed ? 8 : 0) |
          (destination.index >> 3) << 2 |
          source.index >> 3,
      if (bytes < 4) 0x0f,
      bytes == 4 ? (signed ? 0x63 : 0x8b) : (signed ? 0xbe : 0xb6) + bytes - 1,
      0xc0 | (destination.index & 7) << 3 | source.index & 7,
    ]);
  }

  /// Updates flags as if subtracting [right] from [left], preserving registers.
  void compare(Register left, Register right) => _binary(0x39, left, right);

  /// Copies the low 64 bits between SSE registers, preserving flags.
  void moveDouble(FloatRegister destination, FloatRegister source) {
    _bytes.checkOpen();
    if (destination != source) _sse(0xf2, 0x10, destination, source);
  }

  /// Copies raw bits from a general register into a double register.
  void moveBitsToDouble(FloatRegister destination, Register source) =>
      _sse(0x66, 0x6e, destination, source, wide: true);

  /// Copies raw bits from a double register into a general register.
  void moveBitsToGeneral(Register destination, FloatRegister source) =>
      _sse(0x66, 0x7e, source, destination, wide: true);

  /// Converts a signed 64-bit integer using the current MXCSR rounding mode.
  void convertIntToDouble(FloatRegister destination, Register source) =>
      _sse(0xf2, 0x2a, destination, source, wide: true);

  /// Truncates toward zero; masked invalid conversions produce the minimum int64.
  void truncateDoubleToInt(Register destination, FloatRegister source) =>
      _sse(0xf2, 0x2c, destination, source, wide: true);

  /// Converts the low 32-bit float to a double, changing only [destination].
  void convertFloatToDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf3, 0x5a, destination, source);

  /// Rounds a double to the low 32 bits using the current MXCSR rounding mode.
  void convertDoubleToFloat(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x5a, destination, source);

  /// Adds two IEEE 754 doubles in [destination].
  void addDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x58, destination, source);

  /// Subtracts [source] from the double in [destination].
  void subtractDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x5c, destination, source);

  /// Multiplies doubles in [destination], without fusion with another operation.
  void multiplyDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x59, destination, source);

  /// Divides the double in [destination] by [source].
  void divideDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x5e, destination, source);

  /// Computes SQRTSD using the current MXCSR rounding and exception controls.
  void squareRootDouble(FloatRegister destination, FloatRegister source) =>
      _sse(0xf2, 0x51, destination, source);

  /// Sets ZF/PF/CF using UCOMISD; unordered comparisons set all three.
  void compareDouble(FloatRegister left, FloatRegister right) =>
      _sse(0x66, 0x2e, left, right);

  /// Flips one bit, storing its previous value in CF.
  void complementBit(Register register, int bit) {
    RangeError.checkValueInInterval(bit, 0, 63, 'bit');
    _bytes.add([
      0x48 | register.index >> 3,
      0x0f,
      0xba,
      0xf8 | register.index & 7,
      bit,
    ]);
  }

  /// Loads a double with the address constraints of [load].
  void loadDouble(FloatRegister destination, Register base, int offset) =>
      _memory(0x10, destination, base, offset);

  /// Stores a double with the address constraints of [store].
  void storeDouble(FloatRegister source, Register base, int offset) =>
      _memory(0x11, source, base, offset);

  /// Loads 32 float bits with the address constraints of [load].
  void loadFloat(FloatRegister destination, Register base, int offset) =>
      _memory(0x10, destination, base, offset, bytes: 4);

  /// Stores the low 32 bits with the address constraints of [store].
  void storeFloat(FloatRegister source, Register base, int offset) =>
      _memory(0x11, source, base, offset, bytes: 4);

  void _sse(
    int prefix,
    int opcode,
    CpuRegister reg,
    CpuRegister rm, {
    bool wide = false,
  }) {
    final rex = 0x40 | (wide ? 8 : 0) | (reg.index >> 3) << 2 | rm.index >> 3;
    _bytes.add([
      prefix,
      if (rex != 0x40) rex,
      0x0f,
      opcode,
      0xc0 | (reg.index & 7) << 3 | rm.index & 7,
    ]);
  }

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

  /// Creates a local branch destination for this assembler.
  Label label() => _bytes.label();

  /// Binds a local label to the next instruction.
  void bind(Label label) => _bytes.bind(label);

  /// Jumps to a local label, preserving registers and flags.
  void jump(Label target) {
    _bytes.branch(Fixup(length + 1, .x64Jump32), target);
    _bytes.add([0xe9, 0, 0, 0, 0]);
  }

  /// Jumps to a local label when flags match [condition].
  void jumpCondition(Condition condition, Label target) {
    _bytes.branch(Fixup(length + 2, .x64Conditional32), target);
    _bytes.add([0x0f, 0x80 | condition.encoding, 0, 0, 0, 0]);
  }

  /// Updates flags by testing [value] against zero, preserving all registers.
  void test(Register value) => _binary(0x85, value, value);

  /// Emits an unresolved call, pushing the return address on the stack.
  Fixup call() {
    final fixup = Fixup(length + 1, .x64Call32);
    _bytes.add([0xe8, 0, 0, 0, 0]);
    return fixup;
  }

  /// Calls the address in [target], pushing the return address on the stack.
  void callRegister(Register target) {
    _bytes.add([if (target.index >= 8) 0x41, 0xff, 0xd0 | (target.index & 7)]);
  }

  /// Jumps to the address in [target] without changing the stack or flags.
  void jumpRegister(Register target) {
    _bytes.add([if (target.index >= 8) 0x41, 0xff, 0xe0 | (target.index & 7)]);
  }

  /// Loads this instruction's address plus [offset], preserving flags.
  void relativeAddress(Register destination, int offset) {
    final displacement = offset - 7;
    RangeError.checkValueInInterval(
      displacement,
      -0x80000000,
      0x7fffffff,
      'offset',
    );
    _bytes.add([
      0x48 | (destination.index >> 3) << 2,
      0x8d,
      0x05 | (destination.index & 7) << 3,
      displacement & 255,
      (displacement >> 8) & 255,
      (displacement >> 16) & 255,
      (displacement >> 24) & 255,
    ]);
  }

  /// Loads an unresolved RIP-relative address without changing flags.
  Fixup address(Register destination) {
    final fixup = Fixup(length + 3, .x64Address32);
    _bytes.add([
      0x48 | (destination.index >> 3) << 2,
      0x8d,
      0x05 | (destination.index & 7) << 3,
      0,
      0,
      0,
      0,
    ]);
    return fixup;
  }

  /// Loads eight bytes from an unresolved RIP-relative address.
  Fixup loadAddress(Register destination) {
    final fixup = Fixup(length + 3, .x64LoadAddress32);
    _bytes.add([
      0x48 | (destination.index >> 3) << 2,
      0x8b,
      0x05 | (destination.index & 7) << 3,
      0,
      0,
      0,
      0,
    ]);
    return fixup;
  }

  void _checkSize(int bytes) {
    if (![1, 2, 4, 8].contains(bytes)) {
      throw ArgumentError.value(bytes, 'bytes', 'Expected 1, 2, 4 or 8.');
    }
  }

  void _memory(
    int opcode,
    CpuRegister value,
    Register base,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) {
    _checkSize(bytes);
    RangeError.checkValueInInterval(offset, -0x80000000, 0x7fffffff, 'offset');
    final sib = base.index & 7 == 4;
    final floating = value is FloatRegister;
    final load = opcode == 0x8b;
    final extended = !floating && load && bytes < 4;
    if (!floating && bytes < 8) {
      opcode = load
          ? (bytes == 4
                ? (signed ? 0x63 : 0x8b)
                : (signed ? 0xbe : 0xb6) + bytes - 1)
          : (bytes == 1 ? 0x88 : 0x89);
    }
    final rex =
        0x40 |
        (!floating && (bytes == 8 || load && signed) ? 8 : 0) |
        (value.index >> 3) << 2 |
        base.index >> 3;
    final displacement = ByteData(4)..setInt32(0, offset, .little);
    _bytes.add([
      if (floating) bytes == 4 ? 0xf3 : 0xf2,
      if (!floating && !load && bytes == 2) 0x66,
      if (rex != 0x40 || !floating && !load && bytes == 1) rex,
      if (floating || extended) 0x0f,
      opcode,
      0x80 | (value.index & 7) << 3 | base.index & 7,
      if (sib) 0x24,
      ...displacement.buffer.asUint8List(),
    ]);
  }

  /// Returns through the address at the top of the stack.
  void ret() => _bytes.addByte(0xc3);

  /// Enters the operating system, clobbering RCX and R11.
  void syscall() => _bytes.add([0x0f, 0x05]);

  /// Resolves local branches and returns immutable machine code.
  ///
  /// Closes this assembler even if an unbound or out-of-range label prevents
  /// completion. Further emission, label changes and completion are rejected.
  Uint8List finish() => _bytes.finish();

  void _binary(int opcode, Register destination, Register source) =>
      _bytes.add([
        0x48 | (source.index >> 3) << 2 | destination.index >> 3,
        opcode,
        0xc0 | (source.index & 7) << 3 | destination.index & 7,
      ]);
}
