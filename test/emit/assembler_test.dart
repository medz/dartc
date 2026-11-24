import 'dart:typed_data';

import 'package:dartc/lir.dart';
import 'package:dartc/src/emit/arm64/assembler.dart';
import 'package:test/test.dart';

/// Words produced by the system assembler for the same instructions.
void _encodes(int word, void Function(Arm64Assembler assembler) emit) {
  final assembler = Arm64Assembler();
  emit(assembler);
  expect(_words(assembler).map((w) => w.toRadixString(16)), [
    word.toRadixString(16),
  ]);
}

List<int> _words(Arm64Assembler assembler) {
  final data = ByteData.sublistView(assembler.finish());
  return [
    for (var i = 0; i < data.lengthInBytes; i += 4) data.getUint32(i, .little),
  ];
}

/// The value the emitted constant sequence leaves in its register.
int _run(Arm64Assembler assembler) {
  var value = 0;
  for (final word in _words(assembler)) {
    final half = (word >> 21 & 3) * 16, bits = word >> 5 & 0xffff;
    switch (word & 0xff800000) {
      case 0xd2800000:
        value = bits << half;
      case 0x92800000:
        value = ~(bits << half);
      case 0xf2800000:
        value = value & ~(0xffff << half) | bits << half;
      default:
        fail('Unexpected word ${word.toRadixString(16)}');
    }
  }
  return value;
}

void main() {
  test('moves and arithmetic', () {
    _encodes(0xd2d579a3, (a) => a.movz(3, 0xabcd, 2));
    _encodes(0x92a24684, (a) => a.movn(4, 0x1234, 1));
    _encodes(0xf2ffffe5, (a) => a.movk(5, 0xffff, 3));
    _encodes(0xaa1b03e6, (a) => a.mov(6, 27));
    _encodes(0x8b030041, (a) => a.add(1, 2, 3));
    _encodes(0xcb030041, (a) => a.sub(1, 2, 3));
    _encodes(0x8a030041, (a) => a.and(1, 2, 3));
    _encodes(0xaa030041, (a) => a.orr(1, 2, 3));
    _encodes(0xca030041, (a) => a.eor(1, 2, 3));
    _encodes(0x9b037c41, (a) => a.mul(1, 2, 3));
    _encodes(0x9ac30c41, (a) => a.sdiv(1, 2, 3));
    _encodes(0x9b039041, (a) => a.msub(1, 2, 3, 4));
    _encodes(0x9ac32041, (a) => a.lsl(1, 2, 3));
    _encodes(0x9ac32441, (a) => a.lsr(1, 2, 3));
    _encodes(0x9ac32841, (a) => a.asr(1, 2, 3));
  });

  test('immediates', () {
    _encodes(0xf100153f, (a) => a.cmpImmediate(9, 5));
    _encodes(0xb100153f, (a) => a.cmpImmediate(9, -5));
    _encodes(0xf13ffc1f, (a) => a.cmpImmediate(0, 4095));
    _encodes(0x91001c41, (a) => a.addSigned(1, 2, 7));
    _encodes(0xd1001c41, (a) => a.addSigned(1, 2, -7));
    _encodes(0x8b040c71, (a) => a.addScaled(17, 3, 4));
    _encodes(0xd37df041, (a) => a.lslImmediate(1, 2, 3));
    _encodes(0xd340fc41, (a) => a.lslImmediate(1, 2, 0));
    _encodes(0xd3410041, (a) => a.lslImmediate(1, 2, 63));
    _encodes(0xd343fc41, (a) => a.lsrImmediate(1, 2, 3));
    _encodes(0xd37ffc41, (a) => a.lsrImmediate(1, 2, 63));
    _encodes(0x9341fc41, (a) => a.asrImmediate(1, 2, 1));
    _encodes(0x937ffc41, (a) => a.asrImmediate(1, 2, 63));
    _encodes(0x92400041, (a) => a.andMask(1, 2, Arm64Assembler.maskOf(0x1)!));
    _encodes(0xb2400441, (a) => a.orrMask(1, 2, Arm64Assembler.maskOf(0x3)!));
    _encodes(0xd2401c41, (a) => a.eorMask(1, 2, Arm64Assembler.maskOf(0xff)!));
    _encodes(
      0x92403c41,
      (a) => a.andMask(1, 2, Arm64Assembler.maskOf(0xffff)!),
    );
    _encodes(
      0xb27c6c41,
      (a) => a.orrMask(1, 2, Arm64Assembler.maskOf(0xfffffff0)!),
    );
    _encodes(
      0xd2410041,
      (a) => a.eorMask(1, 2, Arm64Assembler.maskOf(-9223372036854775808)!),
    );
    _encodes(
      0x9240f841,
      (a) => a.andMask(1, 2, Arm64Assembler.maskOf(0x7fffffffffffffff)!),
    );
    _encodes(0xb27ff841, (a) => a.orrMask(1, 2, Arm64Assembler.maskOf(-2)!));
    _encodes(
      0xd200f041,
      (a) => a.eorMask(1, 2, Arm64Assembler.maskOf(0x5555555555555555)!),
    );
    _encodes(
      0x9200e441,
      (a) => a.andMask(1, 2, Arm64Assembler.maskOf(0x3333333333333333)!),
    );
    _encodes(
      0xb2009c41,
      (a) => a.orrMask(1, 2, Arm64Assembler.maskOf(0xff00ff00ff00ff)!),
    );
    _encodes(
      0xd2008041,
      (a) => a.eorMask(1, 2, Arm64Assembler.maskOf(0x1000100010001)!),
    );
    _encodes(
      0x92607c41,
      (a) => a.andMask(1, 2, Arm64Assembler.maskOf(-4294967296)!),
    );
    _encodes(
      0xb2441c41,
      (a) => a.orrMask(1, 2, Arm64Assembler.maskOf(-1152921504606846961)!),
    );
    _encodes(0xd2402c41, (a) => a.eorMask(1, 2, Arm64Assembler.maskOf(0xfff)!));
    _encodes(
      0x9240dc41,
      (a) => a.andMask(1, 2, Arm64Assembler.maskOf(0xffffffffffffff)!),
    );

    for (final value in [0, -1, 5, 0x1234, 0x5555555555555554]) {
      expect(Arm64Assembler.maskOf(value), isNull, reason: '$value');
    }
    expect(Arm64Assembler.isSmall(4095), isTrue);
    expect(Arm64Assembler.isSmall(-4095), isTrue);
    expect(Arm64Assembler.isSmall(4096), isFalse);
  });

  test('branches on conditions', () {
    final assembler = Arm64Assembler();
    final label = Label();
    assembler
      ..bind(label)
      ..jumpIf(.lt, label, holds: true)
      ..jumpIf(.lt, label, holds: false)
      ..jumpIfZero(3, label)
      ..jumpIfZero(3, label, isZero: false);
    expect(_words(assembler), [0x5400000b, 0x54ffffea, 0xb4ffffc3, 0xb5ffffa3]);
  });

  test('floating point', () {
    _encodes(0x1e632841, (a) => a.fadd(1, 2, 3));
    _encodes(0x1e633841, (a) => a.fsub(1, 2, 3));
    _encodes(0x1e630841, (a) => a.fmul(1, 2, 3));
    _encodes(0x1e631841, (a) => a.fdiv(1, 2, 3));
    _encodes(0x1e614041, (a) => a.fneg(1, 2));
    _encodes(0x1e61c041, (a) => a.fsqrt(1, 2));
    _encodes(0x1e604366, (a) => a.fmov(6, 27));
    _encodes(0x1e6a2120, (a) => a.fcmp(9, 10));
    _encodes(0x9e620041, (a) => a.intToFloat(1, 2));
    _encodes(0x9e780041, (a) => a.floatToInt(1, 2));
    _encodes(0x9e670041, (a) => a.bitsToFloat(1, 2));
    _encodes(0x9e660041, (a) => a.floatToBits(1, 2));
    _encodes(0xfd7fffe7, (a) => a.load(7, 31, 32760, float: true));
    _encodes(0xfd000ba7, (a) => a.store(7, 29, 16, float: true));
    _encodes(0xfc716be7, (a) => a.loadIndexed(7, 31, 17, float: true));
    _encodes(0xfc316ba7, (a) => a.storeIndexed(7, 29, 17, float: true));
  });

  test('comparisons', () {
    _encodes(0xeb0a013f, (a) => a.cmp(9, 10));
    const words = {
      Condition.eq: 0x9a9f17eb,
      Condition.ne: 0x9a9f07eb,
      Condition.mi: 0x9a9f57eb,
      Condition.lt: 0x9a9fa7eb,
      Condition.le: 0x9a9fc7eb,
      Condition.gt: 0x9a9fd7eb,
      Condition.ge: 0x9a9fb7eb,
      Condition.lo: 0x9a9f27eb,
      Condition.ls: 0x9a9f87eb,
      Condition.hi: 0x9a9f97eb,
      Condition.hs: 0x9a9f37eb,
    };
    expect(words.keys.toSet(), Condition.values.toSet());
    words.forEach((condition, word) {
      _encodes(word, (a) => a.cset(11, condition));
    });
  });

  test('memory, frames and calls', () {
    _encodes(0x913fc3e7, (a) => a.addImmediate(7, 31, 0xff0));
    _encodes(0xf97fffe7, (a) => a.load(7, 31, 32760));
    _encodes(0xf9000ba7, (a) => a.store(7, 29, 16));
    _encodes(0xf8716be7, (a) => a.loadIndexed(7, 31, 17));
    _encodes(0xf8316ba7, (a) => a.storeIndexed(7, 29, 17));
    _encodes(0xa9bf7bfd, (a) => a.pushFrame());
    _encodes(0xa8c17bfd, (a) => a.popFrame());
    _encodes(0x910003fd, (a) => a.addImmediate(29, 31, 0));
    _encodes(0x910003bf, (a) => a.addImmediate(31, 29, 0));
    _encodes(0xcb3063ff, (a) => a.subStack(16));
    _encodes(0xd63f0100, (a) => a.callRegister(8));
    _encodes(0xd65f03c0, (a) => a.ret());
    _encodes(0xd4200020, (a) => a.breakpoint());
  });

  test('loads of every width', () {
    _encodes(0x39801441, (a) => a.loadWidth(.i8, 1, 2, 5));
    _encodes(0x39401441, (a) => a.loadWidth(.u8, 1, 2, 5));
    _encodes(0x79800c41, (a) => a.loadWidth(.i16, 1, 2, 6));
    _encodes(0x79400c41, (a) => a.loadWidth(.u16, 1, 2, 6));
    _encodes(0xb9800841, (a) => a.loadWidth(.i32, 1, 2, 8));
    _encodes(0xb9400841, (a) => a.loadWidth(.u32, 1, 2, 8));
    _encodes(0xf9400841, (a) => a.loadWidth(.i64, 1, 2, 16));
    _encodes(0xf9400841, (a) => a.loadWidth(.ptr, 1, 2, 16));
    _encodes(0xfd400841, (a) => a.loadWidth(.f64, 1, 2, 16));
    final single = Arm64Assembler()..loadWidth(.f32, 1, 2, 8);
    expect(_words(single), [0xbd400841, 0x1e22c021]);
    for (final width in Width.values) {
      final last = 4095 * width.bytes;
      expect(Arm64Assembler.reaches(width, 0), isTrue);
      expect(Arm64Assembler.reaches(width, last), isTrue);
      expect(Arm64Assembler.reaches(width, last + width.bytes), isFalse);
      expect(Arm64Assembler.reaches(width, -width.bytes), isFalse);
      if (width.bytes > 1) expect(Arm64Assembler.reaches(width, 1), isFalse);
      expect(
        () => Arm64Assembler().loadWidth(width, 0, 0, -width.bytes),
        throwsRangeError,
      );
    }
  });

  test('stores of every width', () {
    _encodes(0x39001441, (a) => a.storeWidth(.i8, 1, 2, 5));
    _encodes(0x39001441, (a) => a.storeWidth(.u8, 1, 2, 5));
    _encodes(0x79000c41, (a) => a.storeWidth(.i16, 1, 2, 6));
    _encodes(0x79000c41, (a) => a.storeWidth(.u16, 1, 2, 6));
    _encodes(0xb9000841, (a) => a.storeWidth(.i32, 1, 2, 8));
    _encodes(0xb9000841, (a) => a.storeWidth(.u32, 1, 2, 8));
    for (final width in <Width>[.i64, .ref, .ptr]) {
      _encodes(0xf9000841, (a) => a.storeWidth(width, 1, 2, 16));
    }
    _encodes(0xfd000841, (a) => a.storeWidth(.f64, 1, 2, 16));
    // The value is narrowed in the scratch register, keeping its own.
    final single = Arm64Assembler()..storeWidth(.f32, 1, 2, 8, scratch: 30);
    expect(_words(single), [0x1e62403e, 0xbd00085e]);
    expect(() => Arm64Assembler().storeWidth(.i16, 0, 0, 1), throwsRangeError);
  });

  test('branches backward and forward', () {
    final assembler = Arm64Assembler();
    final back = Label(), ahead = Label();
    assembler
      ..bind(back)
      ..jumpIfZero(12, back)
      ..jump(back)
      ..jumpIfZero(12, ahead)
      ..jump(ahead)
      ..bind(ahead);
    expect(_words(assembler), [0xb400000c, 0x17ffffff, 0xb400004c, 0x14000001]);
    expect(() => assembler.bind(ahead), throwsStateError);
  });

  test('constants', () {
    for (final value in [
      0,
      1,
      -1,
      0xffff,
      0x10000,
      -0x10000,
      0x123456789abcdef0,
      -0x123456789abcdef,
      0x7fffffffffffffff,
      -0x8000000000000000,
      0xffff0000ffff,
      0x0000ffff0000,
    ]) {
      final assembler = Arm64Assembler()..constant(9, value);
      expect(_run(assembler), value);
    }
    expect(_words(Arm64Assembler()..constant(0, 0)).length, 1);
    expect(_words(Arm64Assembler()..constant(0, -1)).length, 1);
    expect(_words(Arm64Assembler()..constant(0, 0x123456789abcdef0)).length, 4);
  });

  test('out-of-range fields are rejected', () {
    final assembler = Arm64Assembler();
    expect(() => assembler.load(0, 31, 32768), throwsRangeError);
    expect(() => assembler.load(0, 31, 4), throwsRangeError);
    expect(() => assembler.store(0, 31, -8), throwsRangeError);
    expect(() => assembler.addImmediate(0, 0, 4096), throwsRangeError);
    expect(() => assembler.movz(0, 0x10000, 0), throwsRangeError);
  });

  test('conditional branches reach 2^18 words either way', () {
    const reach = 1 << 18;
    for (final (words, matcher) in [
      (reach - 1, returnsNormally),
      (reach, throwsRangeError),
    ]) {
      final ahead = Label();
      final assembler = Arm64Assembler()..jumpIfZero(0, ahead);
      for (var i = 1; i < words; i++) {
        assembler.ret();
      }
      expect(() => assembler.bind(ahead), matcher);
    }
    for (final (words, matcher) in [
      (reach, returnsNormally),
      (reach + 1, throwsRangeError),
    ]) {
      final back = Label();
      final assembler = Arm64Assembler()..bind(back);
      for (var i = 0; i < words; i++) {
        assembler.ret();
      }
      expect(() => assembler.jumpIfZero(0, back), matcher);
    }
  });
}
