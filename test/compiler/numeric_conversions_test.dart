@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/numeric_conversions.dart' as sdk;
import 'fixtures/numeric_conversions_ffi.dart';

void main() {
  late NumericConversions native;
  setUpAll(() {
    native = NumericConversions();
    addTearDown(native.close);
  });

  double fromBits(int value) =>
      (ByteData(8)..setUint64(0, value)).getFloat64(0);

  test('rounding directions, halfway neighbors and saturation match SDK', () {
    final cases = <(double, List<int>)>[
      (0.0, [0, 0, 0, 0]),
      (-0.0, [0, 0, 0, 0]),
      (double.minPositive, [0, 0, 1, 0]),
      (-double.minPositive, [0, -1, 0, 0]),
      (1.25, [1, 1, 2, 1]),
      (-1.25, [-1, -2, -1, -1]),
      (1.5, [1, 1, 2, 2]),
      (-1.5, [-1, -2, -1, -2]),
      (fromBits(0x3fdfffffffffffff), [0, 0, 1, 0]),
      (0.5, [0, 0, 1, 1]),
      (fromBits(0x3fe0000000000001), [0, 0, 1, 1]),
      (fromBits(0xbfdfffffffffffff), [0, -1, 0, 0]),
      (-0.5, [0, -1, 0, -1]),
      (fromBits(0xbfe0000000000001), [0, -1, 0, -1]),
      (
        4503599627370495.5,
        [
          4503599627370495,
          4503599627370495,
          4503599627370496,
          4503599627370496,
        ],
      ),
      (4503599627370497.0, List.filled(4, 4503599627370497)),
      (fromBits(0x43dfffffffffffff), List.filled(4, 9223372036854774784)),
      (9223372036854775808.0, List.filled(4, 0x7fffffffffffffff)),
      (-9223372036854775808.0, List.filled(4, -0x8000000000000000)),
      (fromBits(0xc3dfffffffffffff), List.filled(4, -9223372036854774784)),
      (double.maxFinite, List.filled(4, 0x7fffffffffffffff)),
      (-double.maxFinite, List.filled(4, -0x8000000000000000)),
    ];
    for (final (value, results) in cases) {
      for (var mode = 0; mode < 5; mode++) {
        final expected = results[mode == 0 ? 0 : mode - 1];
        expect(sdk.convertDouble(value, mode), expected);
        for (final convert in native.doubles) {
          expect(convert(value, mode), expected, reason: '$value / mode $mode');
        }
      }
    }
  });

  test(
    'integer receivers keep precision through num and conversion methods',
    () {
      for (final value in [
        -0x8000000000000000,
        -9007199254740993,
        -1,
        0,
        9007199254740993,
        0x7fffffffffffffff,
      ]) {
        for (var mode = 0; mode < 5; mode++) {
          for (final convert in native.integers) {
            expect(convert(value, mode), value);
          }
        }
      }
    },
  );

  test(
    'ordinary SDK range checks retain their error fields and string message',
    () {
      for (final value in [
        -0x8000000000000000,
        -7,
        -1,
        0,
        1,
        0x7fffffffffffffff,
      ]) {
        final expected = value < 0 ? value - 1 : value;
        expect(sdk.checkedNonnegative(value), expected);
        expect(native.checkedNonnegative(value), expected);
      }
    },
  );

  test(
    'non-finite conversions throw after evaluation and preserve cleanup',
    () {
      for (final value in [
        double.infinity,
        double.negativeInfinity,
        double.nan,
        fromBits(0x7ff0000000000001),
        0.0,
        -0.5,
        double.maxFinite,
      ]) {
        final expected = value.isFinite ? 124 : 134;
        for (var mode = 0; mode < 5; mode++) {
          for (final boxed in [0, 1]) {
            expect(sdk.conversionFailure(value, mode, boxed), expected);
            expect(native.failure(value, mode, boxed), expected);
          }
        }
      }
      expect(native.savedMessage(double.infinity, 5000), 1);
      expect(native.savedMessage(1.0, 3), 0);
    },
  );
}
