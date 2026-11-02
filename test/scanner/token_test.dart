import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a token refers to original UTF-16 code units and produces a source span',
    () {
      final source = SourceFile(Uri.parse('memory:test.dart'), 'a\u{1F600}b');
      final token = Token(.invalid, source, 1, 3);
      expect(token.length, 2);
      expect(token.lexeme, '\u{1F600}');
      expect(token.span, SourceSpan(source, 1, 3));
      expect(token.span.source, same(source));
    },
  );

  test('token ranges are checked in normal execution', () {
    final source = SourceFile(Uri.parse('memory:test.dart'), 'abc');
    for (final (start, end) in [(-1, 1), (2, 1), (0, 4)]) {
      expect(() => Token(.identifier, source, start, end), throwsRangeError);
    }
    expect(Token(.eof, source, 3, 3).lexeme, '');
  });

  test('preserves short and long ranges throughout a large source', () {
    const boundary = 0x1000000;
    final source = SourceFile(
      Uri.parse('memory:large.dart'),
      'x' * (boundary + 256),
    );
    for (final start in [0, 0x800000, boundary - 1, boundary]) {
      for (final length in [0, 1, 255, 256]) {
        final end = start + length;
        final token = Token(.identifier, source, start, end);
        expect((token.start, token.end, token.length), (start, end, length));
        expect(token.lexeme, 'x' * length);
        expect(token.span, SourceSpan(source, start, end));
      }
    }
  });
}
