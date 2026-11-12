@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/integer_text.dart' as sdk;
import 'fixtures/integer_text_ffi.dart';

void main() {
  late IntegerText native;
  setUpAll(() {
    native = IntegerText();
    addTearDown(native.close);
  });

  (int, int?) expected(String source, int? radix, int mode) {
    try {
      final value = sdk.parse(source, radix, mode);
      return (value == null ? 1 : 0, value);
    } on FormatException {
      return (2, null);
    } on RangeError {
      return (3, null);
    }
  }

  test('parse and tryParse retain signs, radix, whitespace and overflow', () {
    for (final source in [
      '',
      ' ',
      '+',
      '-',
      '0',
      '-0',
      '+00123',
      '0123',
      '123_4',
      '12 3',
      '\u0085\u1680 -42\u3000\ufeff',
      '0x',
      '+0Xff',
      '-0x8000000000000000',
      '0xffffffffffffffff',
      '0x10000000000000000',
      '-0x8000000000000001',
      '9223372036854775807',
      '9223372036854775808',
      '-9223372036854775808',
      '-9223372036854775809',
      'zz',
      'Z1',
      '@',
      ':',
      '\u0000',
      '\ud800',
      '0' * 100 + '7',
      '1' * 100,
    ]) {
      for (final radix in [null, 2, 8, 10, 16, 35, 36, 1, 37, -1]) {
        for (var mode = 0; mode < 4; mode++) {
          expect(
            native.parse(source, radix, mode),
            expected(source, radix, mode),
            reason: '$source/$radix/$mode',
          );
        }
      }
    }
  });

  test('every radix round-trips signed limits and integer method values', () {
    for (final value in [
      -0x8000000000000000,
      -0x7fffffffffffffff,
      -123456789,
      -1,
      0,
      1,
      123456789,
      0x7fffffffffffffff,
    ]) {
      for (var radix = 2; radix <= 36; radix++) {
        for (var mode = 0; mode < 6; mode++) {
          final text = native.format(value, radix, mode);
          expect(
            text,
            sdk.format(value, radix, mode),
            reason: '$value/$radix/$mode',
          );
          expect(native.parse(text, mode < 2 ? radix : 10, mode % 4), (
            0,
            value,
          ));
        }
      }
    }
    for (final radix in [-1, 0, 1, 37]) {
      expect(() => native.format(1, radix, 0), throwsRangeError);
    }
  });
}
