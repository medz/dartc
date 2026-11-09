import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/index_conversions.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('index_conversions');
  });

  test('read and write index checks occur at their own calls', () {
    for (final valid in [false, true]) {
      for (final mode in [0, 1, 2, 3]) {
        fixture.compare('ordinary', [
          valid,
          mode,
        ], () => sdk.ordinary(valid, mode));
        fixture.compare('implicitExtension', [
          valid,
          mode,
        ], () => sdk.implicitExtension(valid, mode));
        if (mode != 0) {
          fixture.compare('explicitExtension', [
            valid,
            mode,
          ], () => sdk.explicitExtension(valid, mode));
        }
      }
    }
  });

  test('non-null if-null reads skip the setter index check', () {
    for (final valid in [false, true]) {
      for (final empty in [false, true]) {
        fixture.compare('ifNullOrdinary', [
          valid,
          empty,
        ], () => sdk.ifNullOrdinary(valid, empty));
        fixture.compare('ifNullImplicit', [
          valid,
          empty,
        ], () => sdk.ifNullImplicit(valid, empty));
        fixture.compare('ifNullExplicit', [
          valid,
          empty,
        ], () => sdk.ifNullExplicit(valid, empty));
      }
    }
  });
}
