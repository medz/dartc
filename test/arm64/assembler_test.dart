import 'dart:typed_data';

import 'package:dartc/arm64.dart';
import 'package:test/test.dart';

void main() {
  test(
    'encodes register fields and signed constants without literal pools',
    () {
      final assembler = Assembler()
        ..move(.x9, .x1)
        ..add(.x0, .x9, .x2)
        ..subtract(.x30, .x29, .x28)
        ..loadImmediate(.x3, -1)
        ..ret();
      final data = ByteData.sublistView(assembler.takeBytes());
      expect(
        [
          for (var offset = 0; offset < data.lengthInBytes; offset += 4)
            data.getUint32(offset, .little),
        ],
        [
          0xaa0103e9,
          0x8b020120,
          0xcb1c03be,
          0xd29fffe3,
          0xf2bfffe3,
          0xf2dfffe3,
          0xf2ffffe3,
          0xd65f03c0,
        ],
      );
      expect(assembler.takeBytes(), isEmpty);
    },
  );
  test('stack operands and branch ranges are validated before encoding', () {
    final assembler = Assembler()
      ..call(0)
      ..call(0);
    final data = ByteData.sublistView(assembler.takeBytes());
    data.patchArm64Call(0, -0x8000000);
    data.patchArm64Call(4, 0x7fffffc);
    expect(data.getUint32(0, .little), 0x96000000);
    expect(data.getUint32(4, .little), 0x95ffffff);
    expect(() => data.patchArm64Call(0, 0x8000000), throwsRangeError);
    expect(() => assembler.call(2), throwsArgumentError);
    expect(() => assembler.add(.sp, .x0, .x1), throwsArgumentError);
    expect(() => assembler.loadImmediate(.sp, 1), throwsArgumentError);
    expect(() => assembler.load(.x0, .sp, 32768), throwsRangeError);
    expect(() => assembler.store(.x0, .sp, 1), throwsArgumentError);
    expect(() => assembler.addImmediate(.sp, .sp, 0x1000000), throwsRangeError);
    assembler
      ..move(.x29, .sp)
      ..load(.x0, .sp, 8)
      ..store(.x1, .sp, 16);
    final stack = ByteData.sublistView(assembler.takeBytes());
    expect(stack.getUint32(0, .little), 0x910003fd);
    expect(stack.getUint32(4, .little), 0xf94007e0);
    expect(stack.getUint32(8, .little), 0xf9000be1);
  });
}
