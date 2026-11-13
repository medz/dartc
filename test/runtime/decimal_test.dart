import 'dart:math';
import 'dart:typed_data';

import '../../sdk/runtime/decimal.dart';
import 'fixtures/decimal_text.dart';

import 'package:test/test.dart';

void main() {
  test(
    'decimal parsing preserves grammar, limits and nearest-even rounding',
    () {
      for (final source in decimalInputs) {
        final expected = double.tryParse(source);
        final text = source.trim();
        final actual = DoubleText.tryParse(text, 0, text.length);
        if (expected?.isNaN == true) {
          expect(actual?.isNaN, isTrue, reason: source);
        } else {
          expect(actual, expected, reason: source);
          expect(actual?.isNegative, expected?.isNegative, reason: source);
        }
      }
      for (final MapEntry(key: source, value: expected)
          in decimalRounding.entries) {
        final bits = ByteData(8)
          ..setFloat64(0, DoubleText.tryParse(source, 0, source.length)!);
        expect(bits.getUint64(0), expected, reason: source);
      }
      expect(DoubleText.tryParse('prefix-1.25suffix', 6, 11), -1.25);
      expect(DoubleText.tryParse(' 1 ', 0, 3), isNull);
      expect(() => DoubleText.tryParse('1', 0, 2), throwsRangeError);
    },
  );

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
      final source = value.toString();
      final parsed = DoubleText.tryParse(source, 0, source.length);
      if (value.isNaN) {
        expect(parsed?.isNaN, isTrue);
      } else {
        expect(parsed, value);
        expect(parsed?.isNegative, value.isNegative);
      }
      if (!value.isFinite) continue;
      expect(DoubleText.exponential(value, -1), value.toStringAsExponential());
      for (final digits in [0, 1, 6, 17, 20]) {
        if (value.abs() < 1e21) {
          expect(
            DoubleText.fixed(value, digits),
            value.toStringAsFixed(digits),
            reason: '$value fixed $digits',
          );
        }
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
  });
}
