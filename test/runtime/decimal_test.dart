import 'dart:math';
import 'dart:typed_data';

import '../../sdk/runtime/decimal.dart';

import 'package:test/test.dart';

void main() {
  test('decimal formatting preserves binary64 rounding and precision', () {
    final random = Random(41037), bits = ByteData(8);
    final values = <double>[
      0,
      -0.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      double.minPositive,
      double.maxFinite,
      2.2250738585072014e-308,
      0.1,
      0.5,
      1.25,
      2.55,
      9.9999,
      -0.00001,
      1e-7,
      1e-6,
      1e20,
      1e21,
      9007199254740992,
      for (var i = 0; i < 600; i++)
        (bits
              ..setUint32(0, random.nextInt(1 << 32))
              ..setUint32(4, random.nextInt(1 << 32)))
            .getFloat64(0),
    ];
    for (final value in values) {
      expect(DoubleText.shortest(value), value.toString(), reason: '$value');
      expect(
        DoubleText.exponential(value, null),
        value.toStringAsExponential(),
      );
      for (final digits in [0, 1, 6, 17, 20]) {
        expect(
          DoubleText.fixed(value, digits),
          value.toStringAsFixed(digits),
          reason: '$value fixed $digits',
        );
        expect(
          DoubleText.exponential(value, digits),
          value.toStringAsExponential(digits),
          reason: '$value exponential $digits',
        );
        expect(
          DoubleText.precision(value, digits + 1),
          value.toStringAsPrecision(digits + 1),
          reason: '$value precision ${digits + 1}',
        );
      }
    }
    expect(() => DoubleText.fixed(double.nan, 21), throwsRangeError);
    expect(() => DoubleText.exponential(0, -1), throwsRangeError);
    expect(() => DoubleText.precision(0, 0), throwsRangeError);
  });
}
