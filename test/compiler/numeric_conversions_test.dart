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

  test('floating quotient converts the division result and preserves integer paths', () {
    for (final (left, right, expected) in <(double, double, int)>[
      (7.0, 2.0, 3),
      (-7.0, 2.0, -3),
      (7.0, -2.0, -3),
      (-0.0, 2.0, 0),
      (double.minPositive, 2.0, 0),
      (1e30, 3.0, 0x7fffffffffffffff),
      (-1e30, 3.0, -0x8000000000000000),
      (7.0, double.infinity, 0),
    ]) {
      for (final mode in [0, 3]) {
        expect(native.truncateDivide(left, right, 0, 1, mode), expected);
        expect(sdk.truncateDivide(left, right, 0, 1, mode), expected);
      }
    }
    for (var mode = 0; mode < 10; mode++) {
      final expected = mode == 9 ? -6 : -3;
      expect(native.truncateDivide(-7.0, 2.0, -7, 2, mode), expected);
    }
    for (final mode in [2, 5, 8]) {
      expect(
        native.truncateDivide(0, 1, 9007199254740993, 1, mode),
        9007199254740992,
      );
    }
    for (final mode in [6, 9]) {
      // Boxed integer division must not round through double at 2^53.
      final expected = mode == 6 ? 9007199254740993 : 18014398509481986;
      expect(native.truncateDivide(0, 1, 9007199254740993, 1, mode), expected);
    }
    for (final (left, right) in [
      (1.0, 0.0),
      (0.0, -0.0),
      (double.infinity, 1.0),
      (double.nan, 1.0),
      (1.0, double.nan),
      (double.maxFinite, double.minPositive),
    ]) {
      for (final boxed in [0, 1]) {
        expect(native.quotientFailure(left, right, boxed), 1134);
        expect(sdk.quotientFailure(left, right, boxed), 1134);
      }
    }
    expect(native.quotientFailure(-7, 2, 0), 1124);
    expect(native.integerQuotientFailure(7, 0), 77);
    expect(
      native.integerQuotientFailure(-0x8000000000000000, -1),
      -0x8000000000000000,
    );
  });

  double fromBits(int value) =>
      (ByteData(8)..setUint64(0, value)).getFloat64(0);

  test(
    'integral doubles preserve range, negative zero and non-finite values',
    () {
      int bits(double value) =>
          (ByteData(8)..setFloat64(0, value)).getUint64(0);
      final cases = <(double, List<double>)>[
        (0.0, List.filled(4, 0.0)),
        (-0.0, List.filled(4, -0.0)),
        (double.minPositive, [0.0, 0.0, 1.0, 0.0]),
        (-double.minPositive, [-0.0, -1.0, -0.0, -0.0]),
        (fromBits(0x3fdfffffffffffff), [0.0, 0.0, 1.0, 0.0]),
        (-fromBits(0x3fdfffffffffffff), [-0.0, -1.0, -0.0, -0.0]),
        (0.5, [0.0, 0.0, 1.0, 1.0]),
        (-0.5, [-0.0, -1.0, -0.0, -1.0]),
        (1.5, [1.0, 1.0, 2.0, 2.0]),
        (-1.5, [-1.0, -2.0, -1.0, -2.0]),
        (
          4503599627370495.5,
          [
            4503599627370495.0,
            4503599627370495.0,
            4503599627370496.0,
            4503599627370496.0,
          ],
        ),
        (
          -4503599627370495.5,
          [
            -4503599627370495.0,
            -4503599627370496.0,
            -4503599627370495.0,
            -4503599627370496.0,
          ],
        ),
        for (final value in [
          4503599627370496.0,
          -4503599627370496.0,
          9223372036854775808.0,
          -9223372036854775808.0,
          double.maxFinite,
          -double.maxFinite,
          double.infinity,
          double.negativeInfinity,
        ])
          (value, List.filled(4, value)),
      ];
      for (final (value, results) in cases) {
        for (var mode = 0; mode < 4; mode++) {
          expect(
            bits(sdk.roundDoubleToDouble(value, mode)),
            bits(results[mode]),
          );
          for (final round in native.floatingRounds) {
            expect(
              bits(round(value, mode)),
              bits(results[mode]),
              reason: '$value / mode $mode',
            );
          }
          expect(native.roundingEffects(value, mode), 12);
        }
      }
      for (final value in [
        fromBits(0x7ff8000000000042),
        fromBits(0xfff8000000000042),
      ]) {
        for (var mode = 0; mode < 4; mode++) {
          for (final round in native.floatingRounds) {
            expect(bits(round(value, mode)), bits(value));
          }
          expect(native.roundingEffects(value, mode), 12);
        }
      }
      for (final value in [
        -0x8000000000000000,
        -9007199254740993,
        0,
        9007199254740993,
        0x7fffffffffffffff,
      ]) {
        for (var mode = 0; mode < 4; mode++) {
          for (final round in native.integerRounds) {
            expect(round(value, mode), value.toDouble());
          }
        }
      }
    },
  );

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
