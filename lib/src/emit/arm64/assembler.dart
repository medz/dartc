import 'dart:typed_data';

import 'package:dartc/lir.dart';

import '../code.dart';
import '../machine.dart';

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
final class Label() implements CodeLabel {
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

  /// Whether [cmpImmediate] can have [value].
  static bool isSmall(int value) => value > -4096 && value < 4096;

  /// Whether [addSigned] can have [value].
  static bool isAddable(int value) => value > -(1 << 24) && value < 1 << 24;

  void cmpImmediate(int n, int value) => _emit(
    (value < 0 ? 0xb1000000 : 0xf1000000) |
        _field(value.abs(), 12, 'compare immediate') << 10 |
        n << 5 |
        zero,
  );

  /// d = n + value.
  void addSigned(int d, int n, int value) {
    final base = value < 0 ? 0xd1000000 : 0x91000000, size = value.abs();
    final high = _field(size >> 12, 12, 'add immediate'), low = size & 0xfff;
    if (high != 0) _emit(base | 1 << 22 | high << 10 | n << 5 | d);
    if (high == 0 || low != 0) {
      _emit(base | low << 10 | (high == 0 ? n : d) << 5 | d);
    }
  }

  /// d = n + m * 2^[shift].
  void addScaled(int d, int n, int m, int shift) =>
      _three(0x8b000000 | _field(shift, 6, 'shift') << 10, d, n, m);

  void lslImmediate(int d, int n, int count) =>
      _emit(0xd3400000 | (-count & 63) << 16 | 63 - count << 10 | n << 5 | d);
  void lsrImmediate(int d, int n, int count) =>
      _emit(0xd340fc00 | _field(count, 6, 'shift') << 16 | n << 5 | d);
  void asrImmediate(int d, int n, int count) =>
      _emit(0x9340fc00 | _field(count, 6, 'shift') << 16 | n << 5 | d);

  /// How `and` and the like have [value], if they can: a run of ones, repeated.
  static int? maskOf(int value) {
    if (value == 0 || value == -1) return null;
    for (var size = 64; size >= 2; size >>= 1) {
      final part = size == 64 ? value : value & ((1 << size) - 1);
      for (var rotation = 0; rotation < size; rotation++) {
        final ones = _runOf(part, size, rotation);
        if (ones == null || !_repeats(value, part, size)) continue;
        final n = size == 64 ? 1 : 0;
        final length = (-(size << 1) & 63 | ones - 1) & 63;
        return n << 12 | rotation << 6 | length;
      }
    }
    return null;
  }

  static bool _repeats(int value, int part, int size) {
    if (size == 64) return true;
    for (var at = 0; at < 64; at += size) {
      if (value >>> at & ((1 << size) - 1) != part) return false;
    }
    return true;
  }

  /// How many ones there are if [part], of [size] bits, is those at the low end
  /// rotated right by [rotation].
  static int? _runOf(int part, int size, int rotation) {
    final mask = size == 64 ? -1 : (1 << size) - 1;
    final turned = rotation == 0
        ? part
        : (part << rotation | (part & mask) >>> (size - rotation)) & mask;
    var ones = 0;
    while (ones < size && turned >>> ones & 1 == 1) {
      ones++;
    }
    final isRun = ones > 0 && ones < size && turned == (1 << ones) - 1;
    return isRun ? ones : null;
  }

  void andMask(int d, int n, int mask) => _masked(0x92000000, d, n, mask);
  void orrMask(int d, int n, int mask) => _masked(0xb2000000, d, n, mask);
  void eorMask(int d, int n, int mask) => _masked(0xd2000000, d, n, mask);

  /// [mask] is what [maskOf] gives.
  void _masked(int base, int d, int n, int mask) =>
      _emit(base | mask << 10 | n << 5 | d);

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

  /// Loads or stores two registers, one after the other, at [offset] from [n].
  ///
  /// [offset] must satisfy [pairReaches].
  void loadPair(int t, int u, int n, int offset, {bool float = false}) =>
      _pair(float ? 0x6d400000 : 0xa9400000, t, u, n, offset);
  void storePair(int t, int u, int n, int offset, {bool float = false}) =>
      _pair(float ? 0x6d000000 : 0xa9000000, t, u, n, offset);

  void _pair(int base, int t, int u, int n, int offset) {
    if (!pairReaches(offset)) throw RangeError('Pair out of reach: $offset');
    _emit(base | (offset ~/ 8 & 0x7f) << 15 | u << 10 | n << 5 | t);
  }

  static bool pairReaches(int offset) =>
      offset % 8 == 0 && offset >= -512 && offset < 512;

  static int _loadOf(Width width) => switch (width) {
    .i8 => 0x39800000,
    .u8 => 0x39400000,
    .i16 => 0x79800000,
    .u16 => 0x79400000,
    .i32 => 0xb9800000,
    .u32 => 0xb9400000,
    .i64 || .ref || .ptr => 0xf9400000,
    .f32 => 0xbd400000,
    .f64 => 0xfd400000,
  };

  /// Loads [width] into [t], extending or converting it to a full register.
  ///
  /// [offset] must satisfy [reaches].
  void loadWidth(Width width, int t, int n, int offset) {
    if (!reaches(width, offset)) {
      throw RangeError('Offset out of reach: $offset');
    }
    _emit(_loadOf(width) | offset ~/ width.bytes << 10 | n << 5 | t);
    if (width == .f32) _three(0x1e22c000, t, t, 0);
  }

  /// As above, at [n] plus [m], which is a number of [width] if it [isScaled].
  void loadWidthAt(Width width, int t, int n, int m, {required bool isScaled}) {
    // The same load, but not with an offset.
    final word = _loadOf(width) & ~(1 << 24) | 0x206800;
    _emit(word | (isScaled ? 1 << 12 : 0) | m << 16 | n << 5 | t);
    if (width == .f32) _three(0x1e22c000, t, t, 0);
  }

  /// Stores the low bytes of [t], narrowing a double in register [scratch].
  ///
  /// [offset] must satisfy [reaches].
  void storeWidth(Width width, int t, int n, int offset, {int scratch = 0}) {
    final word = switch (width) {
      .i8 || .u8 => 0x39000000,
      .i16 || .u16 => 0x79000000,
      .i32 || .u32 => 0xb9000000,
      .i64 || .ref || .ptr => 0xf9000000,
      .f32 => 0xbd000000,
      .f64 => 0xfd000000,
    };
    if (!reaches(width, offset)) {
      throw RangeError('Offset out of reach: $offset');
    }
    if (width == .f32) {
      _three(0x1e624000, scratch, t, 0);
      t = scratch;
    }
    _emit(word | offset ~/ width.bytes << 10 | n << 5 | t);
  }

  /// Whether a load or store of [width] can encode [offset].
  static bool reaches(Width width, int offset) =>
      offset >= 0 && offset % width.bytes == 0 && offset ~/ width.bytes < 4096;

  void pushFrame() => _emit(0xa9bf7bfd);
  void popFrame() => _emit(0xa8c17bfd);
  void callRegister(int n) => _emit(0xd63f0000 | n << 5);
  void jumpRegister(int n) => _emit(0xd61f0000 | n << 5);
  void ret() => _emit(0xd65f03c0);
  void breakpoint() => _emit(0xd4200020);

  void call(String symbol) {
    relocations.add(Relocation(offset, .call26, symbol));
    _emit(0x94000000);
  }

  /// Where symbols of the data of the isolate are in it, which x28 has.
  Map<String, int> isolated = const {};

  void address(int d, String symbol) {
    if (isolated[symbol] case final at?) {
      const isolate = 28;
      if (at >= 1 << 24) throw StateError('The data of isolates is too large.');
      if (at >= 1 << 12) {
        _emit(0x91400000 | (at >> 12) << 10 | isolate << 5 | d);
        addImmediate(d, d, at & 0xfff);
      } else {
        addImmediate(d, isolate, at);
      }
      return;
    }
    relocations.add(Relocation(offset, .page21, symbol));
    _emit(0x90000000 | d);
    relocations.add(Relocation(offset, .pageOffset12, symbol));
    addImmediate(d, d, 0);
  }

  void jump(Label label) => _branch(0x14000000, label, conditional: false);

  /// Jumps when register [t] is 0, or only if it is not.
  void jumpIfZero(int t, Label label, {bool isZero = true}) =>
      _branch((isZero ? 0xb4000000 : 0xb5000000) | t, label, conditional: true);

  /// Jumps when [condition] [holds], or only if it does not.
  void jumpIf(Condition condition, Label label, {required bool holds}) =>
      _branch(
        0x54000000 | condition.code ^ (holds ? 0 : 1),
        label,
        conditional: true,
      );

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
