@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/bound_methods_ffi.dart';

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
