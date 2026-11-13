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

  test(
    'Unicode full case mapping preserves context, UTF-16 and method values',
    () {
      for (final (value, lower, upper) in [
        ('', '', ''),
        ('Ascii I', 'ascii i', 'ASCII I'),
        ('stra\u00dfe', 'stra\u00dfe', 'STRASSE'),
        ('\u00df\u1e9e', '\u00df\u00df', 'SS\u1e9e'),
        ('\u0130I\u0131i', 'i\u0307i\u0131i', '\u0130III'),
        ('I\u0307', 'i\u0307', 'I\u0307'),
        ('\ufb03\ufb04', '\ufb03\ufb04', 'FFIFFL'),
        ('\u0587', '\u0587', '\u0535\u0552'),
        ('\u039f\u03a3', '\u03bf\u03c2', '\u039f\u03a3'),
        ('\u039f\u03a3\u0391', '\u03bf\u03c3\u03b1', '\u039f\u03a3\u0391'),
        ('\u03a3', '\u03c3', '\u03a3'),
        ('A\u03a3\u0301', 'a\u03c2\u0301', 'A\u03a3\u0301'),
        ('A\u03a3\u0301A', 'a\u03c3\u0301a', 'A\u03a3\u0301A'),
        ('A\u0301\u03a3', 'a\u0301\u03c2', 'A\u0301\u03a3'),
        ('A\u03a3.A', 'a\u03c3.a', 'A\u03a3.A'),
        ('A\u03a31A', 'a\u03c21a', 'A\u03a31A'),
        ('\u0345\u03a3', '\u0345\u03c3', '\u0399\u03a3'),
        ('A\u03a3\u0345', 'a\u03c2\u0345', 'A\u03a3\u0399'),
        ('A\u03a3\u0345A', 'a\u03c3\u0345a', 'A\u03a3\u0399A'),
        ('\u{10400}\u{10428}', '\u{10428}\u{10428}', '\u{10400}\u{10400}'),
        ('\u{1e900}\u{1e922}', '\u{1e922}\u{1e922}', '\u{1e900}\u{1e900}'),
        ('\u{104b0}\u{104d8}', '\u{104d8}\u{104d8}', '\u{104b0}\u{104b0}'),
        ('\u13a0\uab70', '\uab70\uab70', '\u13a0\u13a0'),
        ('\u1c90\u10d0', '\u10d0\u10d0', '\u1c90\u1c90'),
        ('\u1c89\u1c8a', '\u1c8a\u1c8a', '\u1c89\u1c89'),
        ('\ud800a\udc00', '\ud800a\udc00', '\ud800A\udc00'),
        (
          '\u0000\u{1f600}\u{10ffff}',
          '\u0000\u{1f600}\u{10ffff}',
          '\u0000\u{1f600}\u{10ffff}',
        ),
      ]) {
        for (var mode = 19; mode <= 24; mode++) {
          final expected = mode.isOdd ? lower : upper;
          expect(
            native.transform(value, '', mode, 0, -1),
            expected,
            reason: '$mode/${value.codeUnits}',
          );
          expect(native.saved(), expected);
        }
      }
    },
  );

  test(
    'case expansions and contextual scans survive allocation and collection',
    () {
      for (final (value, mode, expected) in [
        ('\u00df' * 1500, 20, 'SS' * 1500),
        ('A\u03a3 ' * 500, 19, 'a\u03c2 ' * 500),
        ('A\u03a3${'\u0301' * 2000}A', 19, 'a\u03c3${'\u0301' * 2000}a'),
      ]) {
        expect(native.transform(value, '', mode, 0, -1), expected);
        expect(native.saved(), expected);
      }
    },
  );
}
