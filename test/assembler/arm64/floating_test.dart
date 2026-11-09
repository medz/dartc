import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart';
import 'package:test/test.dart';

void main() {
  test(
    'encodes scalar floating operands and general-register bit transfers',
    () {
      final code = Assembler()
        ..moveDouble(.d31, .d17)
        ..moveBitsToDouble(.d9, .x10)
        ..moveBitsToGeneral(.x11, .d12)
        ..addDouble(.d0, .d1, .d2)
        ..subtractDouble(.d30, .d29, .d28)
        ..multiplyDouble(.d8, .d9, .d10)
        ..divideDouble(.d4, .d5, .d6)
        ..negateDouble(.d13, .d14)
        ..compareDouble(.d1, .d2)
        ..loadDouble(.d31, .sp, 24)
        ..storeDouble(.d0, .x30, 8);
      final bytes = ByteData.sublistView(code.finish());
      expect(
        [
          for (var i = 0; i < bytes.lengthInBytes; i += 4)
            bytes.getUint32(i, .little),
        ],
        [
          0x1e60423f,
          0x9e670149,
          0x9e66018b,
          0x1e622820,
          0x1e7c3bbe,
          0x1e6a0928,
          0x1e6618a4,
          0x1e6141cd,
          0x1e622020,
          0xfd400fff,
          0xfd0007c0,
        ],
      );
      expect(() => code.moveDouble(.d0, .d0), throwsStateError);
    },
  );

  test(
    'invalid floating addresses and SP bit transfers leave the buffer intact',
    () {
      final code = Assembler();
      expect(() => code.loadDouble(.d0, .sp, 32768), throwsRangeError);
      expect(() => code.storeDouble(.d31, .x0, 1), throwsArgumentError);
      expect(() => code.moveBitsToDouble(.d0, .sp), throwsArgumentError);
      expect(() => code.moveBitsToGeneral(.sp, .d0), throwsArgumentError);
      expect(code.finish(), isEmpty);
    },
  );
}
