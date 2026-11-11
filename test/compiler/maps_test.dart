@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/maps.dart' as sdk;
import 'fixtures/maps_ffi.dart';

void main() {
  late Maps native;
  setUpAll(() {
    native = Maps();
    addTearDown(native.close);
  });

  test(
    'map lookup and insertion order survive growth and moving collection',
    () {
      for (final count in [2, 8, 9, 100, 20000]) {
        final expected = count * (count + 1) ~/ 2 + 5 + count;
        expect(sdk.mapBasic(count), expected);
        expect(native.basic(count), expected);
      }
    },
  );
  test('collisions retain original keys and reinsertion appends last', () {
    expect(sdk.mapOrder(), 132);
    expect(native.order(), 132);
  });
  test('null values, numeric equality and non-reflexive keys', () {
    expect(sdk.mapNulls(), 0);
    expect(native.nulls(), 0);
  });
  test('covariant writes check keys and values before changing storage', () {
    for (final mode in [0, 1]) {
      expect(sdk.mapChecked(mode), 14);
      expect(native.checked(mode), 14);
    }
  });
  test('key views are live and iterators detect structural changes', () {
    for (var mode = 0; mode < 5; mode++) {
      final expected = mode == 0 ? 9 : 99;
      expect(sdk.mapIteration(mode), expected);
      expect(native.iteration(mode), expected);
    }
  });
  test('MapBase algorithms execute through the ordinary SDK bodies', () {
    expect(sdk.mapAlgorithms(), 31);
    expect(native.algorithms(), 31);
  });
  test('throwing hash and equality preserve storage and finally', () {
    for (final mode in [0, 1]) {
      final expected = mode == 0 ? 1148 : 1149;
      expect(sdk.mapFailures(mode), expected);
      expect(native.failures(mode), expected);
    }
  });
  test('keys and values remain rooted across collection and native calls', () {
    expect(sdk.mapReferences(30000), 44998);
    expect(native.references(30000), 44998);
    expect(sdk.mapSaved(), 15002);
    expect(native.saved(), 15002);
  });
  test('default Map retains LinkedHashMap and iterable type arguments', () {
    expect(sdk.mapViews(), 23);
    expect(native.views(), 23);
  });
  test('hash and equality callbacks can trigger moving collection', () {
    expect(sdk.mapCallbackRoots(), 40);
    expect(native.callbackRoots(), 40);
  });
  test('user overrides, method values and map patterns retain dispatch', () {
    for (final mode in [0, 1]) {
      final expected = mode == 0 ? 6 : 26;
      expect(sdk.mapDispatch(mode), expected);
      expect(native.dispatch(mode), expected);
    }
  });
}
