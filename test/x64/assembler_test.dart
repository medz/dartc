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
}
