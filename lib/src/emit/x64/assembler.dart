import 'dart:typed_data';

import 'package:dartc/lir.dart' show Width;

import '../code.dart';
import '../machine.dart';

/// x64 condition codes, by encoding.
enum Condition(final int code) {
  below(2),
  aboveOrEqual(3),
  equal(4),
  notEqual(5),
  belowOrEqual(6),
  above(7),
  parity(10),
  noParity(11),
  less(12),
  greaterOrEqual(13),
  lessOrEqual(14),
  greater(15),
}

/// Operations on two words, by the opcode that stores to the first one.
enum WordOp(final int code) {
  add(0x01),
  or(0x09),
  and(0x21),
  sub(0x29),
  xor(0x31),
  cmp(0x39),
  test(0x85),
  mov(0x89),
}

/// Operations on one word, by the opcode and what is in the place of another
/// register.
enum UnaryOp(final int code, final int extension) {
  neg(0xf7, 3),
  idiv(0xf7, 7),

  // By the count in rcx.
  shl(0xd3, 4),
  shr(0xd3, 5),
  sar(0xd3, 7),
  call(0xff, 2),
  jmp(0xff, 4),
}

/// Operations on two doubles, by opcode.
enum DoubleOp(final int code) {
  sqrt(0x51),
  add(0x58),
  mul(0x59),
  sub(0x5c),
  div(0x5e),
}

/// A branch destination inside the code being assembled.
final class Label() implements CodeLabel {
  int? _offset;
  final _uses = <int>[];
}

/// Memory at a base register plus an offset, and perhaps an index register.
final class const Memory(
  final int base, {
  final int offset = 0,
  final int? index,

  /// Whether the index is a number of 8 bytes.
  final bool isScaled = false,
});

/// Encodes 64-bit x64 instructions, with registers given by number.
final class X64Assembler() {
  static const rax = 0, rcx = 1, rdx = 2, rbx = 3, rsp = 4, rbp = 5;
  static const rsi = 6, rdi = 7, r8 = 8, r9 = 9, r10 = 10, r11 = 11;

  final _bytes = <int>[];
  final relocations = <Relocation>[];

  int get offset => _bytes.length;

  Uint8List finish() => Uint8List.fromList(_bytes);

  void _byte(int value) => _bytes.add(value & 0xff);

  void _word32(int value) {
    for (var i = 0; i < 4; i++) {
      _byte(value >> i * 8);
    }
  }

  static bool _fits(int value, int bits) =>
      value >= -(1 << (bits - 1)) && value < 1 << (bits - 1);

  /// Whether the low byte of a register needs a prefix to be told from others.
  static bool _hasPrefixedByte(int register) => register >= 4;

  /// Emits [prefix], if it is not 0, and what tells high registers and words,
  /// where that is needed.
  void _rex(
    int reg,
    int rm, {
    int index = 0,
    bool wide = true,
    bool always = false,
    int prefix = 0,
  }) {
    if (prefix != 0) _byte(prefix);
    final bits =
        (wide ? 8 : 0) |
        (reg >= 8 ? 4 : 0) |
        (index >= 8 ? 2 : 0) |
        (rm >= 8 ? 1 : 0);
    if (bits != 0 || always) _byte(0x40 | bits);
  }

  void _registers(int reg, int rm) => _byte(0xc0 | (reg & 7) << 3 | (rm & 7));

  /// Emits what tells [reg] and [memory].
  void _memory(int reg, Memory memory) {
    final Memory(:base, :offset, :index, :isScaled) = memory;
    // rbp and r13 always have an offset.
    final mode = offset == 0 && base & 7 != rbp
        ? 0
        : _fits(offset, 8)
        ? 1
        : 2;
    if (!_fits(offset, 32)) throw RangeError('Offset out of reach: $offset');
    if (index != null || base & 7 == rsp) {
      if (index == rsp) throw ArgumentError.value(index, 'index');
      _byte(mode << 6 | (reg & 7) << 3 | 4);
      _byte((isScaled ? 0xc0 : 0) | ((index ?? rsp) & 7) << 3 | (base & 7));
    } else {
      _byte(mode << 6 | (reg & 7) << 3 | (base & 7));
    }
    if (mode == 1) _byte(offset);
    if (mode == 2) _word32(offset);
  }

  /// Emits an instruction of [opcodes] with [reg] and [memory].
  void _access(
    List<int> opcodes,
    int reg,
    Memory memory, {
    bool wide = true,
    bool always = false,
    int prefix = 0,
  }) {
    _rex(
      reg,
      memory.base,
      index: memory.index ?? 0,
      wide: wide,
      always: always,
      prefix: prefix,
    );
    opcodes.forEach(_byte);
    _memory(reg, memory);
  }

  /// d = d op m, for words.
  void binary(WordOp op, int d, int m) {
    _rex(m, d);
    _byte(op.code);
    _registers(m, d);
  }

  void mov(int d, int m) => binary(.mov, d, m);

  void unary(UnaryOp op, int d) {
    final isBranch = op == .call || op == .jmp;
    _rex(0, d, wide: !isBranch);
    _byte(op.code);
    _registers(op.extension, d);
  }

  /// d = d * m.
  void imul(int d, int m) {
    _rex(d, m);
    _byte(0x0f);
    _byte(0xaf);
    _registers(d, m);
  }

  /// d = m * [value], which fits 32 bits.
  void imulImmediate(int d, int m, int value) {
    _rex(d, m);
    _byte(0x69);
    _registers(d, m);
    _word32(value);
  }

  /// Extends the sign of rax to rdx.
  void cqo() {
    _byte(0x48);
    _byte(0x99);
  }

  /// Whether instructions can have [value].
  static bool isImmediate(int value) => _fits(value, 32);

  /// d = d op [value], for those that [WordOp] has except `mov` and `test`.
  void binaryImmediate(WordOp op, int d, int value) {
    final isByte = _fits(value, 8);
    _rex(0, d);
    _byte(isByte ? 0x83 : 0x81);
    // The operation is part of the other opcodes.
    _registers(op.code >> 3, d);
    isByte ? _byte(value) : _word32(value);
  }

  void subStack(int bytes) => binaryImmediate(.sub, rsp, bytes);

  /// Moves the stack pointer down to a multiple of 16.
  void alignStack() => binaryImmediate(.and, rsp, -16);

  /// Shifts [d] by [count].
  void shiftImmediate(UnaryOp op, int d, int count) {
    _rex(0, d);
    _byte(0xc1);
    _registers(op.extension, d);
    _byte(count);
  }

  /// Loads any 64-bit constant.
  void constant(int d, int value) {
    if (value >= 0 && value < 1 << 32) {
      _rex(0, d, wide: false);
      _byte(0xb8 | d & 7);
      _word32(value);
    } else if (_fits(value, 32)) {
      _rex(0, d);
      _byte(0xc7);
      _registers(0, d);
      _word32(value);
    } else {
      _rex(0, d);
      _byte(0xb8 | d & 7);
      _word32(value);
      _word32(value >> 32);
    }
  }

  /// d = the address of [memory].
  void lea(int d, Memory memory) => _access([0x8d], d, memory);

  void load(int d, Memory memory, {bool float = false}) =>
      loadWidth(float ? .f64 : .i64, d, memory);

  void store(int s, Memory memory, {bool float = false}) =>
      storeWidth(float ? .f64 : .i64, s, memory);

  /// Loads [width] into [d], extending or converting it to a full register.
  void loadWidth(Width width, int d, Memory memory) {
    switch (width) {
      case .i8:
        _access([0x0f, 0xbe], d, memory);
      case .u8:
        _access([0x0f, 0xb6], d, memory, wide: false);
      case .i16:
        _access([0x0f, 0xbf], d, memory);
      case .u16:
        _access([0x0f, 0xb7], d, memory, wide: false);
      case .i32:
        _access([0x63], d, memory);
      case .u32:
        _access([0x8b], d, memory, wide: false);
      case .i64 || .ref || .ptr:
        _access([0x8b], d, memory);
      case .f32:
        _access([0x0f, 0x10], d, memory, wide: false, prefix: 0xf3);
        _float(0xf3, 0x5a, d, d);
      case .f64:
        _access([0x0f, 0x10], d, memory, wide: false, prefix: 0xf2);
    }
  }

  /// Stores the low bytes of [s], narrowing a double in register [scratch].
  void storeWidth(Width width, int s, Memory memory, {int scratch = 0}) {
    switch (width) {
      case .i8 || .u8:
        _access([0x88], s, memory, wide: false, always: _hasPrefixedByte(s));
      case .i16 || .u16:
        _access([0x89], s, memory, wide: false, prefix: 0x66);
      case .i32 || .u32:
        _access([0x89], s, memory, wide: false);
      case .i64 || .ref || .ptr:
        _access([0x89], s, memory);
      case .f32:
        _float(0xf2, 0x5a, scratch, s);
        _access([0x0f, 0x11], scratch, memory, wide: false, prefix: 0xf3);
      case .f64:
        _access([0x0f, 0x11], s, memory, wide: false, prefix: 0xf2);
    }
  }

  void _float(int prefix, int code, int d, int m, {bool wide = false}) {
    _rex(d, m, wide: wide, prefix: prefix);
    _byte(0x0f);
    _byte(code);
    _registers(d, m);
  }

  /// d = d op m, for doubles, or the root of m.
  void floatBinary(DoubleOp op, int d, int m) => _float(0xf2, op.code, d, m);
  void fmov(int d, int m) => _float(0x66, 0x28, d, m);
  void fxor(int d, int m) => _float(0x66, 0x57, d, m);
  void fcmp(int n, int m) => _float(0x66, 0x2e, n, m);

  /// Converts the signed word in [m] to a double, and back toward zero.
  void intToFloat(int d, int m) => _float(0xf2, 0x2a, d, m, wide: true);
  void floatToInt(int d, int m) => _float(0xf2, 0x2c, d, m, wide: true);

  /// Copies bits between the banks.
  void bitsToFloat(int d, int m) => _float(0x66, 0x6e, d, m, wide: true);
  void floatToBits(int d, int m) => _float(0x66, 0x7e, m, d, wide: true);

  /// Sets the low byte of [d] to 1 if [condition] holds, else to 0.
  void setByte(int d, Condition condition) {
    _rex(0, d, wide: false, always: _hasPrefixedByte(d));
    _byte(0x0f);
    _byte(0x90 | condition.code);
    _registers(0, d);
  }

  /// d = the low byte of m.
  void extendByte(int d, int m) {
    _rex(d, m, wide: false, always: _hasPrefixedByte(m));
    _byte(0x0f);
    _byte(0xb6);
    _registers(d, m);
  }

  void push(int s) {
    _rex(0, s, wide: false);
    _byte(0x50 | s & 7);
  }

  void pop(int d) {
    _rex(0, d, wide: false);
    _byte(0x58 | d & 7);
  }

  /// Goes back to the frame before.
  void leave() => _byte(0xc9);
  void ret() => _byte(0xc3);
  void breakpoint() => _byte(0xcc);
  void nop() => _byte(0x90);

  void _symbol(RelocationKind kind, String symbol) {
    relocations.add(Relocation(offset, kind, symbol));
    _word32(0);
  }

  void call(String symbol) {
    _byte(0xe8);
    _symbol(.call32, symbol);
  }

  /// Emits an instruction of [opcode] with [reg] and the memory at [symbol].
  void _atSymbol(int opcode, int reg, String symbol) {
    _rex(reg, 0);
    _byte(opcode);
    _byte((reg & 7) << 3 | 5);
    _symbol(.relative32, symbol);
  }

  void address(int d, String symbol) => _atSymbol(0x8d, d, symbol);
  void loadSymbol(int d, String symbol) => _atSymbol(0x8b, d, symbol);
  void storeSymbol(int s, String symbol) => _atSymbol(0x89, s, symbol);

  /// Compares register [d] with the word at [symbol].
  void cmpSymbol(int d, String symbol) => _atSymbol(0x3b, d, symbol);

  void callLabel(Label label) {
    _byte(0xe8);
    _label(label);
  }

  void jump(Label label) {
    _byte(0xe9);
    _label(label);
  }

  /// Jumps when [condition] [holds], or only if it does not.
  void jumpIf(Condition condition, Label label, {bool holds = true}) {
    _byte(0x0f);
    _byte(0x80 | condition.code ^ (holds ? 0 : 1));
    _label(label);
  }

  /// Emits the distance from the next instruction to [label].
  void _label(Label label) {
    final at = offset;
    _word32(0);
    if (label._offset case final target?) {
      _patch(at, target);
    } else {
      label._uses.add(at);
    }
  }

  /// Places [label] here and completes the branches waiting for it.
  void bind(Label label) {
    if (label._offset != null) throw StateError('The label is already bound.');
    label._offset = offset;
    for (final at in label._uses) {
      _patch(at, offset);
    }
  }

  void _patch(int at, int target) {
    final distance = target - (at + 4);
    for (var i = 0; i < 4; i++) {
      _bytes[at + i] = distance >> i * 8 & 0xff;
    }
  }
}
