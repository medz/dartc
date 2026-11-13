@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/string_operations.dart' as sdk;
import 'fixtures/string_operations_ffi.dart';

void main() {
  late StringOperations native;
  setUpAll(() {
    native = StringOperations();
    addTearDown(native.close);
  });

  test(
    'string transformations preserve UTF-16, ranges and collection lifetime',
    () {
      for (final value in [
        '',
        'banana',
        'A\u0000\u{1f600}\ud800Z',
        '\u0085\u1680\u2000 A\u3000\ufeff',
      ]) {
        for (var mode = 0; mode <= 17; mode++) {
          for (final pattern in ['', 'a', 'na', '🙂']) {
            final first = mode == 4
                ? 3
                : mode == 5 || mode == 6
                ? value.length + 2
                : 0;
            final expected = sdk.transform(value, pattern, mode, first, -1);
            expect(
              native.transform(value, pattern, mode, first, -1),
              expected,
              reason: '$mode/$value/$pattern',
            );
            expect(native.saved(), expected);
          }
        }
      }
      for (final (mode, first, last) in [
        (0, -1, 2),
        (0, 2, 1),
        (0, 0, 99),
        (7, -1, 2),
        (8, -1, -1),
        (11, 99, -1),
      ]) {
        expect(
          () => native.transform('abc', 'b', mode, first, last),
          throwsRangeError,
        );
        expect(
          () => sdk.transform('abc', 'b', mode, first, last),
          throwsRangeError,
        );
      }
      for (final mode in [5, 6]) {
        expect(
          native.transform('abc', 'x', mode, -0x8000000000000000, -1),
          'abc',
        );
      }
      expect(native.transform('abc', '', 4, -1, -1), '');
    },
  );

  test('search and Pattern methods preserve boundaries, empty matches and dispatch', () {
    for (final value in ['', 'banana', '\u{1f600}\ud800']) {
      for (final pattern in ['', 'a', 'na', '🙂', '\ud800']) {
        for (final mode in [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          10,
          11,
          12,
          13,
          16,
          17,
        ]) {
          for (final start in [-1, 0, value.length, value.length + 1]) {
            expect(
              native.inspect(value, pattern, mode, start),
              sdk.inspect(value, pattern, mode, start),
              reason: '$value/$pattern/$mode/$start',
            );
          }
        }
      }
    }
  });

  test('replacement preserves long slices, Unicode and callback order', () {
    for (final value in [
      '${'a' * 499}x',
      '${'a' * 2047}x',
      '${'\u1000' * 2048}x',
      '\ud800x\u{1f600}x',
    ]) {
      for (final mode in [9, 10, 18]) {
        expect(
          native.transform(value, 'x', mode, 0, -1),
          sdk.transform(value, 'x', mode, 0, -1),
          reason: '$mode/${value.length}',
        );
      }
    }
    for (final pattern in ['', 'a', 'missing']) {
      expect(
        native.transform('aba', pattern, 18, 0, -1),
        sdk.transform('aba', pattern, 18, 0, -1),
      );
    }
  });
}
