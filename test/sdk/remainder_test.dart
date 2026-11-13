import 'package:test/test.dart';

import '../../sdk/patches/remainder.dart';
import '../support/floating_reduction.dart';

void main() {
  test('floating reduction agrees with exact binary arithmetic', () {
    for (final (a, b) in floatingReductionCases()) {
      final expected = exactFloatingReduction(a, b);
      for (final (actual, value) in [
        (floatingRemainder(a, b), expected.remainder),
        (floatingModulo(a, b), expected.modulo),
      ]) {
        expect(actual, value.isNaN ? isNaN : value, reason: '$a / $b');
        if (value == 0) expect(actual.isNegative, value.isNegative);
      }
    }
  });

  test('negative tiny modulo retains binary64 rounding at the upper bound', () {
    expect(floatingRemainder(-double.minPositive, 1), -double.minPositive);
    expect(floatingModulo(-double.minPositive, 1), 1.0);
    expect(floatingModulo(-double.minPositive, -1), 1.0);
    expect(floatingModulo(-5.5, 2), 0.5);
  });
}
