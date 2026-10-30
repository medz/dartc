import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:example.dart');

  group('SourceSpan', () {
    test('extracts a half-open UTF-16 range', () {
      final source = SourceFile(uri, 'A\u{1F600}\r\nB');
      final span = SourceSpan(source, 1, 3);
      expect(span.source, same(source));
      expect(span.text, '\u{1F600}');
      expect(span.length, 2);
      expect(span.isEmpty, isFalse);
      expect(source.lineInfo.location(span.start), (line: 1, column: 2));
      expect(source.lineInfo.location(span.end), (line: 1, column: 4));
      expect(SourceSpan(source, 0, source.length).text, source.text);
    });

    test('preserves code units even inside a surrogate pair', () {
      final source = SourceFile(uri, '\u{1F600}');
      expect(SourceSpan(source, 0, 1).text.codeUnits, [0xD83D]);
      expect(SourceSpan(source, 1, 2).text.codeUnits, [0xDE00]);
    });

    test('allows empty spans at every boundary including EOF', () {
      for (final text in ['', 'a\r\nb']) {
        final source = SourceFile(uri, text);
        for (var offset = 0; offset <= source.length; offset++) {
          final span = SourceSpan(source, offset, offset);
          expect(span.isEmpty, isTrue);
          expect(span.length, 0);
          expect(span.text, isEmpty);
        }
      }
    });

    test('rejects reversed and out-of-bounds ranges', () {
      final source = SourceFile(uri, 'abc');
      for (final bounds in [
        (start: -1, end: 0),
        (start: 0, end: -1),
        (start: 2, end: 1),
        (start: 0, end: 4),
        (start: 4, end: 4),
      ]) {
        expect(
          () => SourceSpan(source, bounds.start, bounds.end),
          throwsRangeError,
          reason: '$bounds',
        );
      }
    });

    test('compares bounds within the same snapshot', () {
      final source = SourceFile(uri, 'abc');
      final first = SourceSpan(source, 0, 2);
      final sameRange = SourceSpan(source, 0, 2);
      expect(first, sameRange);
      expect(first.hashCode, sameRange.hashCode);
      expect({first, sameRange}, hasLength(1));
      expect(first, isNot(SourceSpan(source, 1, 2)));
      expect(first, isNot(SourceSpan(source, 0, 3)));
      expect(first, isNot(Object()));
    });

    test('does not equate different snapshots sharing a URI', () {
      final original = SourceFile(uri, 'abc');
      final unchanged = SourceFile(uri, 'abc');
      final edited = SourceFile(uri, 'xyz');
      final span = SourceSpan(original, 0, 3);
      expect(span, isNot(SourceSpan(unchanged, 0, 3)));
      expect(span, isNot(SourceSpan(edited, 0, 3)));
      expect(span.text, 'abc');
    });
  });
}
