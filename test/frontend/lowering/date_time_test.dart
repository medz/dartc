import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/date_time.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load(
      'date_time',
      sources: await SdkSources.load(),
    );
  });

  test(
    'epoch construction preserves units and rejects out-of-range values',
    () {
      for (final value in [-8640000000000000, -1, 0, 1, 8640000000000000]) {
        fixture.compare('milliseconds', [value], () => value * 1000);
      }
      for (final micros in [false, true]) {
        final max = micros ? 8640000000000000000 : 8640000000000000;
        for (final value in [-max - 1, -max, 0, max, max + 1]) {
          fixture.compare('validation', [
            value,
            micros,
          ], () => sdk.validation(value, micros));
        }
      }
    },
  );

  test('instant comparison is separate from zone identity', () {
    for (final value in [-8640000000000000000, -1, 0, 8640000000000000000]) {
      fixture.compare('identity', [value], () => true);
      for (final other in [-8640000000000000000, -1, 0, 8640000000000000000]) {
        fixture.compare('compare', [
          value,
          other,
        ], () => sdk.compare(value, other));
      }
    }
  });
}
