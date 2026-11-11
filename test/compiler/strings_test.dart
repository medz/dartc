@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/strings.dart' as sdk;
import 'fixtures/strings_ffi.dart';

void main() {
  late Strings native;
  setUpAll(() {
    native = Strings();
    addTearDown(native.close);
  });

  const units = <List<int>>[
    [],
    [0x44, 0x61, 0x72, 0x74],
    [0x41, 0, 0xd83d, 0xde00, 0x5a],
    [0xd800, 0xdc00, 0xdfff],
  ];
  test(
    'UTF-16 length and units survive calls, method values and collection',
    () {
      expect(native.length(-1), -1);
      for (final (kind, expected) in units.indexed) {
        expect(sdk.stringLength(kind), expected.length);
        expect(native.length(kind), expected.length);
        for (final (index, value) in expected.indexed) {
          for (final mode in [0, 1, 2, 3]) {
            expect(sdk.stringRead(kind, index, mode, 0), value);
            expect(native.read(kind, index, mode, 40000), value);
          }
        }
      }
    },
  );

  test('invalid code-unit reads preserve RangeError and evaluation order', () {
    for (final (kind, expected) in units.indexed) {
      for (final index in [
        -0x8000000000000000,
        -1,
        expected.length,
        0x7fffffffffffffff,
      ]) {
        for (final bound in [0, 1]) {
          expect(sdk.stringFailure(kind, index, bound), 1234);
          expect(native.failure(kind, index, bound), 1234);
        }
      }
    }
  });
}
