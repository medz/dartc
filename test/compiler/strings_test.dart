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
        for (final bound in [0, 1, 2]) {
          expect(sdk.stringFailure(kind, index, bound), 1234);
          expect(native.failure(kind, index, bound), 1234);
        }
      }
    }
  });

  test('constructed strings preserve Unicode, indexing and value equality', () {
    for (final (code, units) in [
      (0, [0]),
      (0x61, [0x61]),
      (0xffff, [0xffff]),
      (0xd800, [0xd800]),
      (0xdfff, [0xdfff]),
      (0x10000, [0xd800, 0xdc00]),
      (0x1f600, [0xd83d, 0xde00]),
      (0x10ffff, [0xdbff, 0xdfff]),
    ]) {
      for (final (index, unit) in units.indexed) {
        for (final bound in [0, 1]) {
          final expected = units.length * 0x10000 + unit;
          expect(sdk.stringConstruct(code, index, bound), expected);
          expect(native.construct(code, index, bound), expected);
        }
      }
    }
  });

  test(
    'variable payloads survive growth, copying, globals and bound receivers',
    () {
      for (final (code, width, first, last) in [
        (0x61, 1, 0x61, 0x61),
        (0x1f600, 2, 0xd83d, 0xde00),
      ]) {
        for (final rounds in [0, 3, 16]) {
          final expected =
              (width << rounds) * 0x100000000 + first * 0x10000 + last;
          expect(sdk.stringGrowth(code, rounds, 20000), expected);
          expect(native.growth(code, rounds, 20000), expected);
          expect(
            native.saved((width << rounds) - 1),
            (width << rounds) * 0x10000 + last,
          );
        }
      }
    },
  );

  test(
    'invalid character codes throw before unused results can be removed',
    () {
      for (final code in [
        -0x8000000000000000,
        -1,
        0x110000,
        0x7fffffffffffffff,
      ]) {
        for (final bound in [0, 1]) {
          expect(sdk.stringInvalidCode(code, bound), 234);
          expect(native.invalidCode(code, bound), 234);
        }
      }
    },
  );
}
