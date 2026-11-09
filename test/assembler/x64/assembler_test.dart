import 'dart:typed_data';

import 'package:dartc/assembler/x64.dart';
import 'package:test/test.dart';

void main() {
  test('general memory operands encode extended bases and the RSP/R12 SIB', () {
    final assembler = Assembler()
      ..load(.r9, .r13, -8)
      ..store(.r10, .r12, 16);
    final address = assembler.address(.r10);
    expect(address.offset, 18);
    expect(assembler.finish(), [
      0x4d,
      0x8b,
      0x8d,
      0xf8,
      0xff,
      0xff,
      0xff,
      0x4d,
      0x89,
      0x94,
      0x24,
      16,
      0,
      0,
      0,
      0x4c,
      0x8d,
      0x15,
      0,
      0,
      0,
      0,
    ]);
  });
  test('encodes REX register extensions and little-endian immediates', () {
    final assembler = Assembler()
      ..move(.r9, .r10)
      ..add(.rax, .r9)
      ..subtract(.r10, .rdi)
      ..negate(.r11)
      ..loadImmediate(.r8, -1)
      ..ret();
    expect(assembler.finish(), [
      0x4d,
      0x89,
      0xd1,
      0x4c,
      0x01,
      0xc8,
      0x49,
      0x29,
      0xfa,
      0x49,
      0xf7,
      0xdb,
      0x49,
      0xb8,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      0xc3,
    ]);
    expect(assembler.finish, throwsStateError);
  });
  test('encodes multiplication with destination in the ModRM reg field', () {
    final assembler = Assembler()
      ..multiply(.r9, .rdi)
      ..multiply(.rax, .r10)
      ..multiply(.r11, .r9)
      ..multiply(.rax, .rax)
      ..bitAnd(.r9, .rdi)
      ..bitOr(.rax, .r10)
      ..bitXor(.r11, .r9);
    expect(assembler.finish(), [
      0x4c,
      0x0f,
      0xaf,
      0xcf,
      0x49,
      0x0f,
      0xaf,
      0xc2,
      0x4d,
      0x0f,
      0xaf,
      0xd9,
      0x48,
      0x0f,
      0xaf,
      0xc0,
      0x49,
      0x21,
      0xf9,
      0x4c,
      0x09,
      0xd0,
      0x4d,
      0x31,
      0xcb,
    ]);
  });
  test('validates stack offsets and preserves extended register fields', () {
    final assembler = Assembler();
    expect(() => assembler.load(.rax, .rsp, 0x80000000), throwsRangeError);
    expect(() => assembler.addImmediate(.rsp, 0x80000000), throwsRangeError);
    assembler
      ..push(.rbp)
      ..load(.r9, .rsp, 8)
      ..store(.r10, .rsp, 16)
      ..pop(.rbp);
    expect(assembler.finish(), [
      0x55,
      0x4c,
      0x8b,
      0x8c,
      0x24,
      8,
      0,
      0,
      0,
      0x4c,
      0x89,
      0x94,
      0x24,
      16,
      0,
      0,
      0,
      0x5d,
    ]);
  });
  test('uses byte-register REX prefixes and resolves local labels', () {
    final assembler = Assembler(),
        start = assembler.label(),
        end = assembler.label();
    assembler
      ..bind(start)
      ..compare(.r9, .r10)
      ..setCondition(.rsi, .lessThan)
      ..setCondition(.r9, .equal)
      ..test(.r10)
      ..jumpCondition(.equal, end)
      ..jump(start)
      ..bind(end)
      ..ret();
    final bytes = assembler.finish(), data = ByteData.sublistView(bytes);
    expect(bytes.take(22), [
      0x4d,
      0x39,
      0xd1,
      0x40,
      0x0f,
      0x9c,
      0xc6,
      0x48,
      0x0f,
      0xb6,
      0xf6,
      0x41,
      0x0f,
      0x94,
      0xc1,
      0x4d,
      0x0f,
      0xb6,
      0xc9,
      0x4d,
      0x85,
      0xd2,
    ]);
    expect(data.getInt32(24, .little), 5);
    expect(data.getInt32(29, .little), -33);
    expect(() => bytes[0] = 0, throwsUnsupportedError);
    expect(() => assembler.move(.rax, .rax), throwsStateError);
    expect(assembler.ret, throwsStateError);
    expect(assembler.label, throwsStateError);
    expect(() => assembler.bind(start), throwsStateError);
    expect(assembler.finish, throwsStateError);
  });
  test('rejects foreign, duplicate and unbound labels before emission', () {
    final assembler = Assembler(), label = assembler.label();
    final foreign = Assembler().label();
    expect(() => assembler.bind(foreign), throwsArgumentError);
    expect(() => assembler.jumpCondition(.equal, foreign), throwsArgumentError);
    expect(assembler.length, 0);
    assembler.bind(label);
    expect(() => assembler.bind(label), throwsStateError);
    assembler.jump(assembler.label());
    expect(assembler.finish, throwsStateError);
    expect(assembler.finish, throwsStateError);
  });
}
