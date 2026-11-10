@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import '../support/numeric_order.dart';
import 'fixtures/bound_methods_ffi.dart';
import 'fixtures/bound_methods.dart' as sdk;

void main() {
  late BoundMethods native;
  setUpAll(() {
    native = BoundMethods();
    addTearDown(native.close);
  });

  test(
    'extraction retains dispatch, defaults, receiver and direct super body',
    () {
      for (final count in [0, 40000]) {
        expect(native.calls(0, count), 242916);
        expect(native.calls(1, count), 525816);
      }
    },
  );

  test('bound equality uses receiver identity and selected method', () {
    for (final count in [0, 40000]) {
      expect(native.identity(count), 1111111111);
    }
  });

  test('Object and Function views preserve equality and hash contracts', () {
    for (final count in [0, 40000]) {
      expect(sdk.functionObjects(count), 131071);
      expect(native.objects(count), 131071);
    }
  });

  test('boxed numeric equality and hashes agree with scalar views', () {
    for (final (number, floating) in [
      (0, -0.0),
      (0, 5e-324),
      (-1, -1.0),
      (42, 42.5),
      (9007199254740992, 9007199254740992.0),
      (9007199254740993, 9007199254740992.0),
      (0x7fffffffffffffff, 9223372036854775808.0),
      (-0x8000000000000000, -9223372036854775808.0),
      (0, double.nan),
      (0, double.infinity),
      (0, double.negativeInfinity),
    ]) {
      expect(
        native.scalars(number, floating),
        255 | (numericOrder(number, floating) == 0 ? 256 : 0),
        reason: '$number, $floating',
      );
    }
  });

  test('generic methods retain actual owner types and method binders', () {
    for (final count in [0, 40000]) {
      expect(native.generic(count), 43211);
    }
  });

  test(
    'extraction and invocation checks preserve evaluation order and cleanup',
    () {
      for (final count in [0, 40000]) {
        expect(native.checks(count), 123456);
      }
    },
  );
}
