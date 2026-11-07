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
}
