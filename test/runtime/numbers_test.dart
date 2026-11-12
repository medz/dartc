import 'dart:math';
import 'dart:typed_data';

import '../../sdk/runtime/numbers.dart';

import 'package:test/test.dart';

void main() {
  test(
    'floating reduction preserves exact remainder, modulo and signed zero',
    () {
      final bits = ByteData(8), random = Random(314);
      final edges = [
        0.0,
        -0.0,
        1.0,
        -1.0,
        2.5,
        -2.5,
        double.minPositive,
        double.maxFinite,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ];
      double sample() =>
          (bits
                ..setUint32(0, random.nextInt(1 << 32))
                ..setUint32(4, random.nextInt(1 << 32)))
              .getFloat64(0);
      for (final (a, b) in [
        for (final a in edges)
          for (final b in edges) (a, b),
        for (var i = 0; i < 300; i++) (sample(), sample()),
      ]) {
        for (final (actual, expected) in [
          (floatingRemainder(a, b), a.remainder(b)),
          (floatingModulo(a, b), a % b),
        ]) {
          expect(actual, expected.isNaN ? isNaN : expected, reason: '$a / $b');
          if (expected == 0) expect(actual.isNegative, expected.isNegative);
        }
      }
    },
  );
}
