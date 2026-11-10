@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/nullability.dart' as sdk;
import 'fixtures/nullability_ffi.dart';

void main() {
  late Nullability native;
  setUpAll(() => native = Nullability());
  tearDownAll(() => native.close());

  test('nullable scalar calls, tests and refinements preserve values', () {
    for (final mode in [-1, 0, 1, 2]) {
      expect(native.integer(mode), sdk.integer(mode));
      expect(native.boolean(mode), sdk.boolean(mode));
      expect(native.predicates(mode), mode < 0 ? 18 : 45);
      expect(native.predicates(mode), sdk.predicates(mode));
      final actual = native.floating(mode), expected = sdk.floating(mode);
      if (expected.isNaN) {
        expect(actual.isNaN, isTrue);
      } else {
        expect(actual, expected);
        expect(actual.isNegative, expected.isNegative);
      }
    }
  });

  test('null short circuits evaluate each required side effect once', () {
    for (final mode in [-1, 0, 1]) {
      expect(native.coalescing(mode), sdk.coalescing(mode));
      expect(native.shortCircuit(mode), sdk.shortCircuit(mode));
    }
    expect(native.coalescing(-1), 8);
    expect(native.shortCircuit(-1), 20);
    expect(native.shortCircuit(0), 2);
    expect(native.shortCircuit(1), 32);
  });

  test('nullable references survive calls and simultaneous loop transfers', () {
    for (final count in [0, 1, 2, 3, 6, 31]) {
      expect(native.rotate(count), sdk.rotate(count));
    }
  });
}
