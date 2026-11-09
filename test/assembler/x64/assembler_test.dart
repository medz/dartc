import 'dart:typed_data';

import 'package:dartc/assembler/x64.dart';
import 'package:test/test.dart';

void main() {
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
  test('validates stack offsets and preserves extended register fields', () {
    final assembler = Assembler();
    expect(() => assembler.loadStack(.rax, 0x80000000), throwsRangeError);
    expect(() => assembler.addImmediate(.rsp, 0x80000000), throwsRangeError);
    assembler
      ..push(.rbp)
      ..loadStack(.r9, 8)
      ..storeStack(.r10, 16)
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
