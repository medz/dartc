import 'dart:typed_data';

import '../code.dart';

/// ARM64 condition codes, by encoding.
enum Condition(final int code) {
  eq(0),
  ne(1),
  hs(2),
  lo(3),
  hi(8),
  ls(9),
  mi(4),
  ge(10),
  lt(11),
  gt(12),
  le(13),
}

/// A branch destination inside the code being assembled.
final class Label() {
  int? _offset;
  final _uses = <(int, {bool conditional})>[];
}

/// Encodes 64-bit ARM64 instructions, with registers given by number.
///
/// Number 31 is the stack pointer or the zero register, as the instruction
/// defines.
final class Arm64Assembler() {
  static const frame = 29, stack = 31, zero = 31;

  final _words = <int>[];
  final relocations = <Relocation>[];

  int get offset => _words.length * 4;

  Uint8List finish() {
    final data = ByteData(offset);
    for (final (i, word) in _words.indexed) {
      data.setUint32(i * 4, word, .little);
    }
    return data.buffer.asUint8List();
  }

  void _emit(int word) => _words.add(word);

  static int _field(int value, int bits, String what) =>
      value >= 0 && value < 1 << bits
      ? value
      : throw RangeError('$what does not fit $bits bits: $value');

  static int _signed(int value, int bits, String what) {
    final limit = 1 << (bits - 1);
    if (value < -limit || value >= limit) {
      throw RangeError('$what does not fit $bits bits: $value');
    }
    return value & ((1 << bits) - 1);
  }

  void _wide(int base, int d, int immediate, int half) => _emit(
    base | half << 21 | _field(immediate, 16, 'move immediate') << 5 | d,
  );

  void movz(int d, int immediate, int half) =>
      _wide(0xd2800000, d, immediate, half);
  void movn(int d, int immediate, int half) =>
      _wide(0x92800000, d, immediate, half);
  void movk(int d, int immediate, int half) =>
      _wide(0xf2800000, d, immediate, half);

  /// Loads any 64-bit constant.
  void constant(int d, int value) {
    int part(int half) => value >> half * 16 & 0xffff;
    // Start from all zeros or all ones, whichever leaves less to fill in.
    final ones = [0, 1, 2, 3].where((i) => part(i) == 0xffff).length;
    final zeros = [0, 1, 2, 3].where((i) => part(i) == 0).length;
    final fill = ones > zeros ? 0xffff : 0;
    final halves = [0, 1, 2, 3].where((i) => part(i) != fill).toList();
    if (halves.isEmpty) halves.add(0);
    for (final (i, half) in halves.indexed) {
      if (i > 0) {
        movk(d, part(half), half);
      } else if (fill == 0) {
        movz(d, part(half), half);
      } else {
        movn(d, part(half) ^ 0xffff, half);
      }
    }
  }

  void _three(int base, int d, int n, int m) =>
      _emit(base | m << 16 | n << 5 | d);

  void mov(int d, int m) => _three(0xaa000000, d, zero, m);
  void add(int d, int n, int m) => _three(0x8b000000, d, n, m);
  void sub(int d, int n, int m) => _three(0xcb000000, d, n, m);
  void and(int d, int n, int m) => _three(0x8a000000, d, n, m);
  void orr(int d, int n, int m) => _three(0xaa000000, d, n, m);
  void eor(int d, int n, int m) => _three(0xca000000, d, n, m);
  void mul(int d, int n, int m) => _three(0x9b007c00, d, n, m);
  void sdiv(int d, int n, int m) => _three(0x9ac00c00, d, n, m);
  void lsl(int d, int n, int m) => _three(0x9ac02000, d, n, m);
  void lsr(int d, int n, int m) => _three(0x9ac02400, d, n, m);
  void asr(int d, int n, int m) => _three(0x9ac02800, d, n, m);

  /// d = a - n * m.
  void msub(int d, int n, int m, int a) =>
      _three(0x9b008000 | a << 10, d, n, m);

  // Doubles, with registers of the other bank.
  void fadd(int d, int n, int m) => _three(0x1e602800, d, n, m);
  void fsub(int d, int n, int m) => _three(0x1e603800, d, n, m);
  void fmul(int d, int n, int m) => _three(0x1e600800, d, n, m);
  void fdiv(int d, int n, int m) => _three(0x1e601800, d, n, m);
  void fneg(int d, int n) => _three(0x1e614000, d, n, 0);
  void fsqrt(int d, int n) => _three(0x1e61c000, d, n, 0);
  void fmov(int d, int n) => _three(0x1e604000, d, n, 0);
  void fcmp(int n, int m) => _three(0x1e602000, 0, n, m);

  /// Converts the signed word in [n] to a double, and back toward zero.
  void intToFloat(int d, int n) => _three(0x9e620000, d, n, 0);
  void floatToInt(int d, int n) => _three(0x9e780000, d, n, 0);

  /// Copies bits between the banks.
  void bitsToFloat(int d, int n) => _three(0x9e670000, d, n, 0);
  void floatToBits(int d, int n) => _three(0x9e660000, d, n, 0);

  void cmp(int n, int m) => _three(0xeb000000, zero, n, m);

  /// d = 1 if [condition] holds, else 0.
  void cset(int d, Condition condition) =>
      _emit(0x9a9f07e0 | (condition.code ^ 1) << 12 | d);

  /// d = n + immediate, where d and n may be the stack pointer.
  void addImmediate(int d, int n, int immediate) => _emit(
    0x91000000 | _field(immediate, 12, 'add immediate') << 10 | n << 5 | d,
  );

  /// Lowers the stack pointer by register [m].
  void subStack(int m) => _three(0xcb206000, stack, stack, m);

  /// The largest byte offset [load] and [store] accept.
  static const maxOffset = 4095 * 8;

  int _scaled(int offset) {
    if (offset % 8 != 0) throw RangeError('Unaligned word offset: $offset');
    return _field(offset ~/ 8, 12, 'word offset');
  }

  /// [float] selects a register of the double bank for [t].
  void load(int t, int n, int offset, {bool float = false}) => _emit(
    (float ? 0xfd400000 : 0xf9400000) | _scaled(offset) << 10 | n << 5 | t,
  );
  void store(int t, int n, int offset, {bool float = false}) => _emit(
    (float ? 0xfd000000 : 0xf9000000) | _scaled(offset) << 10 | n << 5 | t,
  );

  /// Addressing by base [n], possibly the stack pointer, plus register [m].
  void loadIndexed(int t, int n, int m, {bool float = false}) =>
      _three(float ? 0xfc606800 : 0xf8606800, t, n, m);
  void storeIndexed(int t, int n, int m, {bool float = false}) =>
      _three(float ? 0xfc206800 : 0xf8206800, t, n, m);

  void pushFrame() => _emit(0xa9bf7bfd);
  void popFrame() => _emit(0xa8c17bfd);
  void callRegister(int n) => _emit(0xd63f0000 | n << 5);
  void ret() => _emit(0xd65f03c0);
  void breakpoint() => _emit(0xd4200020);

  void call(String symbol) {
    relocations.add(Relocation(offset, .call26, symbol));
    _emit(0x94000000);
  }

  void address(int d, String symbol) {
    relocations.add(Relocation(offset, .page21, symbol));
    _emit(0x90000000 | d);
    relocations.add(Relocation(offset, .pageOffset12, symbol));
    addImmediate(d, d, 0);
  }

  void jump(Label label) => _branch(0x14000000, label, conditional: false);

  /// Jumps when register [t] is 0.
  void jumpIfZero(int t, Label label) =>
      _branch(0xb4000000 | t, label, conditional: true);

  void _branch(int base, Label label, {required bool conditional}) {
    final at = _words.length;
    _emit(base);
    if (label._offset case final target?) {
      _patch(at, target, conditional: conditional);
    } else {
      label._uses.add((at, conditional: conditional));
    }
  }

  /// Places [label] here and completes the branches waiting for it.
  void bind(Label label) {
    if (label._offset != null) throw StateError('The label is already bound.');
    label._offset = _words.length;
    for (final (at, :conditional) in label._uses) {
      _patch(at, _words.length, conditional: conditional);
    }
  }

  void _patch(int at, int target, {required bool conditional}) {
    _words[at] |= conditional
        ? _signed(target - at, 19, 'conditional branch') << 5
        : _signed(target - at, 26, 'branch');
  }
}
