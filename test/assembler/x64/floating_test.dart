import 'package:dartc/assembler/x64.dart';
import 'package:test/test.dart';

void main() {
  test(
    'encodes SSE prefixes, register extensions, bit transfers and addresses',
    () {
      final code = Assembler()
        ..moveDouble(.xmm9, .xmm10)
        ..moveBitsToDouble(.xmm8, .r9)
        ..moveBitsToGeneral(.r10, .xmm11)
        ..convertIntToDouble(.xmm12, .r13)
        ..truncateDoubleToInt(.r14, .xmm15)
        ..addDouble(.xmm0, .xmm1)
        ..subtractDouble(.xmm9, .xmm2)
        ..multiplyDouble(.xmm2, .xmm9)
        ..divideDouble(.xmm15, .xmm14)
        ..compareDouble(.xmm8, .xmm1)
        ..complementBit(.r11, 63)
        ..loadDouble(.xmm9, .r12, 16)
        ..storeDouble(.xmm10, .r13, -8);
      expect(
        code.finish(),
        ('f2 45 0f 10 ca 66 4d 0f 6e c1 66 4d 0f 7e da '
                'f2 4d 0f 2a e5 f2 4d 0f 2c f7 '
                'f2 0f 58 c1 f2 44 0f 5c ca f2 41 0f 59 d1 f2 45 0f 5e fe '
                '66 44 0f 2e c1 49 0f ba fb 3f '
                'f2 45 0f 10 8c 24 10 00 00 00 f2 45 0f 11 95 f8 ff ff ff')
            .split(' ')
            .map((v) => int.parse(v, radix: 16)),
      );
      expect(() => code.moveDouble(.xmm0, .xmm0), throwsStateError);
    },
  );

  test('rejects floating displacements and bit indexes before emission', () {
    final code = Assembler();
    expect(() => code.loadDouble(.xmm0, .rsp, 0x80000000), throwsRangeError);
    expect(() => code.storeDouble(.xmm15, .r12, -0x80000001), throwsRangeError);
    expect(() => code.complementBit(.r11, 64), throwsRangeError);
    expect(code.finish(), isEmpty);
  });
}
