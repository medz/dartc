import 'dart:typed_data';

import 'package:dartc/x64.dart';
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
    expect(assembler.takeBytes(), [
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
    expect(assembler.takeBytes(), isEmpty);
  });
  test(
    'calls preserve signed displacement limits and stack register fields',
    () {
      final assembler = Assembler()
        ..call(0)
        ..call(0);
      final data = ByteData.sublistView(assembler.takeBytes());
      data.patchX64Call(1, -0x80000000);
      data.patchX64Call(6, 0x7fffffff);
      expect(data.getInt32(1, .little), -0x80000000);
      expect(data.getInt32(6, .little), 0x7fffffff);
      expect(() => data.patchX64Call(1, 0x80000000), throwsRangeError);
      expect(() => data.patchX64Call(0, 0), throwsArgumentError);
      expect(() => assembler.loadStack(.rax, 0x80000000), throwsRangeError);
      assembler
        ..push(.rbp)
        ..loadStack(.r9, 8)
        ..storeStack(.r10, 16)
        ..pop(.rbp);
      expect(assembler.takeBytes(), [
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
    },
  );
}
