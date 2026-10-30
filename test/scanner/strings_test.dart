import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ScanResult scanText(String text) =>
    scan(SourceFile(Uri.parse('memory:strings.dart'), text));

void main() {
  group('strings', () {
    final completeStrings = [
      "''",
      '""',
      "'plain'",
      '"plain"',
      "'''a\r\nb\rc\nd'''",
      '"""a"b""c"""',
      r"'\n\r\f\b\t\v\a\$\\\x41\u0042\u{1F600}'",
      r"'\u{D800}\uDFFF\u{10FFFF}'",
      r"r'$name ${expression} \u{NOT_HEX}\'",
      'r"""\$a\r\n\\"b""c"""',
      "'\u{1F600}\uD800\u0000\u2028\u2029'",
    ];
    for (var i = 0; i < completeStrings.length; i++) {
      test('preserves complete string $i without decoding it', () {
        final text = completeStrings[i];
        final result = scanText(text);
        expect(result.hasErrors, isFalse);
        expect(result.tokens.map((t) => t.kind), <TokenKind>[
          .stringLiteral,
          .eof,
        ]);
        expect(result.tokens.first.lexeme, text);
      });
    }

    test('keeps adjacent strings distinct', () {
      final result = scanText("'a'/* between */r'b' \"c\"");
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.lexeme), ["'a'", "r'b'", '"c"', '']);
      expect(result.comments.single.lexeme, '/* between */');
    });

    test('splits simple interpolations and retains empty string segments', () {
      final result = scanText(r'"$a$b $this $await"');
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.kind), <TokenKind>[
        .stringStart,
        .interpolationIdentifier,
        .identifier,
        .stringMiddle,
        .interpolationIdentifier,
        .identifier,
        .stringMiddle,
        .interpolationIdentifier,
        .keywordThis,
        .stringMiddle,
        .interpolationIdentifier,
        .keywordAwait,
        .stringEnd,
        .eof,
      ]);
      expect(result.tokens.map((t) => t.lexeme), [
        '"',
        r'$',
        'a',
        '',
        r'$',
        'b',
        ' ',
        r'$',
        'this',
        ' ',
        r'$',
        'await',
        '"',
        '',
      ]);
    });

    test('tracks braces only in the current interpolated expression', () {
      const text = r'''"a${{'key': "${f(/* } */ () { return '}'; })}"}}b"''';
      final result = scanText(text);
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.lexeme), [
        '"a',
        r'${',
        '{',
        "'key'",
        ':',
        '"',
        r'${',
        'f',
        '(',
        '(',
        ')',
        '{',
        'return',
        "'}'",
        ';',
        '}',
        ')',
        '}',
        '"',
        '}',
        '}',
        'b"',
        '',
      ]);
      expect(
        result.tokens.where((t) => t.kind == .interpolationEnd),
        hasLength(2),
      );
      expect(result.comments.single.lexeme, '/* } */');
    });

    test(
      'allows line breaks inside an interpolation of a single-line string',
      () {
        final result = scanText('"\${\n 1 + 2\n}"');
        expect(result.hasErrors, isFalse);
        expect(result.tokens.map((t) => t.lexeme), [
          '"',
          r'${',
          '1',
          '+',
          '2',
          '}',
          '"',
          '',
        ]);
      },
    );

    test('nested interpolation uses bounded call depth', () {
      const depth = 10000;
      final text =
          '${List.filled(depth, '"\${').join()}0${List.filled(depth, '}"').join()}';
      final result = scanText(text);
      expect(result.hasErrors, isFalse);
      expect(result.tokens, hasLength(depth * 4 + 2));
      expect(result.tokens.last.start, text.length);
    });

    for (final text in [r'"$"', r'"$3"', r'"$$"']) {
      test('diagnoses invalid interpolation in $text', () {
        final result = scanText('$text; after');
        expect(result.hasErrors, isTrue);
        expect(
          result.diagnostics.map((d) => d.code),
          everyElement('scanner.invalid_interpolation'),
        );
        expect(result.tokens.map((t) => t.lexeme), [text, ';', 'after', '']);
      });
    }

    for (final escape in [
      r'\x',
      r'\x0',
      r'\xGG',
      r'\u',
      r'\u123',
      r'\u{}',
      r'\u{123',
      r'\u{0000000}',
      r'\u{110000}',
    ]) {
      test(
        'rejects malformed escape $escape without swallowing the next token',
        () {
          final result = scanText("'$escape'; next");
          expect(result.diagnostics.single.code, 'scanner.invalid_escape');
          expect(result.tokens.map((t) => t.lexeme), [
            "'$escape'",
            ';',
            'next',
            '',
          ]);
        },
      );
    }

    for (final prefix in ["'", "r'", "'''", "r'''", r'"$a']) {
      test('reports an unfinished string after $prefix', () {
        final result = scanText('${prefix}text');
        expect(result.diagnostics.single.code, 'scanner.unterminated_string');
        expect(result.diagnostics.single.span!.start, 0);
        expect(result.tokens.last.kind, TokenKind.eof);
      });
    }

    test(
      'recovers at a single-line string newline, including an escaped newline',
      () {
        for (final text in ["'unfinished\r\nnext", "'unfinished\\\r\nnext"]) {
          final result = scanText(text);
          expect(result.diagnostics.single.code, 'scanner.unterminated_string');
          expect(result.tokens[result.tokens.length - 2].lexeme, 'next');
        }
      },
    );

    test(
      'reports every unfinished interpolation without inventing closing tokens',
      () {
        final result = scanText(r'"${"${1');
        expect(result.diagnostics.map((d) => d.code), [
          'scanner.unterminated_interpolation',
          'scanner.unterminated_interpolation',
        ]);
        expect(result.tokens.map((t) => t.lexeme), [
          '"',
          r'${',
          '"',
          r'${',
          '1',
          '',
        ]);
        expect(
          result.tokens.where((t) => t.kind == .interpolationEnd),
          isEmpty,
        );
      },
    );
  });
}
