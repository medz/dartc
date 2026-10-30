import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  group('LineInfo', () {
    final cases = [
      (name: 'empty source', text: '', positions: [(line: 1, column: 1)]),
      (
        name: 'source without a line ending',
        text: 'ab',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 1, column: 3),
        ],
      ),
      (
        name: 'LF',
        text: 'a\nb',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 2, column: 1),
          (line: 2, column: 2),
        ],
      ),
      (
        name: 'trailing CR',
        text: 'a\r',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 2, column: 1),
        ],
      ),
      (
        name: 'trailing CRLF',
        text: 'a\r\n',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 1, column: 3),
          (line: 2, column: 1),
        ],
      ),
      (
        name: 'mixed line endings',
        text: 'a\r\nb\rc\nd',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 1, column: 3),
          (line: 2, column: 1),
          (line: 2, column: 2),
          (line: 3, column: 1),
          (line: 3, column: 2),
          (line: 4, column: 1),
          (line: 4, column: 2),
        ],
      ),
      (
        name: 'consecutive line endings',
        text: '\r\r\n\n',
        positions: [
          (line: 1, column: 1),
          (line: 2, column: 1),
          (line: 2, column: 2),
          (line: 3, column: 1),
          (line: 4, column: 1),
        ],
      ),
      (
        name: 'blank lines and trailing LF',
        text: 'a\n\nb\n',
        positions: [
          (line: 1, column: 1),
          (line: 1, column: 2),
          (line: 2, column: 1),
          (line: 3, column: 1),
          (line: 3, column: 2),
          (line: 4, column: 1),
        ],
      ),
      (
        name: 'UTF-16 columns without text normalization',
        text: '\uFEFF\tA\u{1F600}e\u0301\u2028\u2029\uD800\nx',
        positions: [
          for (var column = 1; column <= 11; column++)
            (line: 1, column: column),
          (line: 2, column: 1),
          (line: 2, column: 2),
        ],
      ),
    ];

    for (final testCase in cases) {
      test(testCase.name, () {
        final info = LineInfo(testCase.text);
        expect(info.length, testCase.text.length);
        expect(info.lineCount, testCase.positions.last.line);
        expect(testCase.positions.length, info.length + 1);
        for (var offset = 0; offset <= info.length; offset++) {
          final expected = testCase.positions[offset];
          expect(info.location(offset), expected, reason: 'offset $offset');
          expect(info.offsetOf(expected.line, expected.column), offset);
        }
      });
    }

    test('finds arbitrary lines without relying on query order', () {
      final info = LineInfo(List.filled(4096, 'x\n').join());
      expect(info.lineCount, 4097);
      for (final offset in [8192, 0, 6143, 1, 2048, 4095, 8191, 2]) {
        final expected = (line: offset ~/ 2 + 1, column: offset % 2 + 1);
        expect(info.location(offset), expected);
        expect(info.offsetOf(expected.line, expected.column), offset);
      }
    });

    test('rejects offsets before the source and beyond EOF', () {
      for (final text in ['', 'ab', 'a\r\n']) {
        final info = LineInfo(text);
        expect(() => info.location(-1), throwsRangeError);
        expect(() => info.location(info.length + 1), throwsRangeError);
      }
    });

    test('rejects invalid lines and columns instead of crossing lines', () {
      final info = LineInfo('a\r\nb');
      for (final line in [-1, 0, 3]) {
        expect(() => info.offsetOf(line, 1), throwsRangeError);
      }
      for (final line in [1, 2]) {
        for (final column in [-1, 0]) {
          expect(() => info.offsetOf(line, column), throwsRangeError);
        }
      }
      expect(() => info.offsetOf(1, 4), throwsRangeError);
      expect(() => info.offsetOf(2, 3), throwsRangeError);
      expect(() => LineInfo('').offsetOf(1, 2), throwsRangeError);
      expect(() => LineInfo('a\n').offsetOf(1, 3), throwsRangeError);
      expect(() => LineInfo('a\n').offsetOf(2, 2), throwsRangeError);
    });
  });
}
