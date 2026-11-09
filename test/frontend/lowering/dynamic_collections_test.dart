import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/dynamic_collections.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('dynamic_collections');
  });

  test('dynamic sequences check elements, preserving protocol effects', () {
    for (final bad in [false, true]) {
      fixture.compare('dynamicLoop', [bad], () => sdk.dynamicLoop(bad));
      fixture.compare('dynamicCollectionLoop', [
        bad,
      ], () => sdk.dynamicCollectionLoop(bad));
      for (final set in [false, true]) {
        fixture.compare('dynamicSequenceSpread', [
          bad,
          set,
        ], () => sdk.dynamicSequenceSpread(bad, set));
      }
    }
    fixture.compare('broadDynamicValues', [], sdk.broadDynamicValues);
    for (final bad in [false, true]) {
      for (final map in [false, true]) {
        fixture.compare('dynamicNullAwareValues', [
          bad,
          map,
        ], () => sdk.dynamicNullAwareValues(bad, map));
      }
    }
  });

  test(
    'dynamic source checks precede protocol getters and null-aware spreads',
    () {
      for (var mode = 0; mode < 4; mode++) {
        fixture.compare('dynamicDuck', [mode], () => sdk.dynamicDuck(mode));
      }
      for (var mode = 0; mode < 4; mode++) {
        for (final aware in [false, true]) {
          fixture.compare('dynamicNull', [
            mode,
            aware,
          ], () => sdk.dynamicNull(mode, aware));
        }
      }
    },
  );

  test('map spreads choose checked entries or unchecked forEach', () {
    for (final bad in [false, true]) {
      for (var target = 0; target < 5; target++) {
        fixture.compare('dynamicMapSpread', [
          bad,
          target,
        ], () => sdk.dynamicMapSpread(bad, target));
      }
      for (final checked in [false, true]) {
        fixture.compare('staticDynamicMapSpread', [
          bad,
          checked,
        ], () => sdk.staticDynamicMapSpread(bad, checked));
      }
      fixture.compare('staticObjectMapSpread', [
        bad,
      ], () => sdk.staticObjectMapSpread(bad));
    }
    for (var failure = 0; failure < 3; failure++) {
      fixture.compare('mapEntryOrder', [
        failure,
      ], () => sdk.mapEntryOrder(failure));
    }
    for (final bad in [false, true]) {
      fixture.compare('genericCheckedMapCase', [
        bad,
      ], () => sdk.genericCheckedMapCase(bad));
    }
    fixture.compare('genericMapCase', [], sdk.genericMapCase);
    fixture.compare('entryValues', [], sdk.entryValues);
    fixture.compare('mapEntriesLiveView', [], sdk.mapEntriesLiveView);
    fixture.compare('customMapEntries', [], sdk.customMapEntries);
    fixture.compare('genericEntriesCase', [], sdk.genericEntriesCase);
  });
}
