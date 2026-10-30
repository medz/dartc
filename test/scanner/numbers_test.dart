import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ScanResult scanText(String text) =>
    scan(SourceFile(Uri.parse('memory:numbers.dart'), text));

void main() {
  group('number tokens', () {
    const cases = <String, TokenKind>{
      '0': .integer,
      '00123': .integer,
      '123456789012345678901234567890': .integer,
      '1__000_000': .integer,
      '0x0': .hexadecimalInteger,
      '0XAb_Cd__Ef': .hexadecimalInteger,
      '0xffffffffffffffffffffffff': .hexadecimalInteger,
      '.5': .doubleLiteral,
      '1.0': .doubleLiteral,
      '1e9': .doubleLiteral,
      '1E+9': .doubleLiteral,
      '.5e-2': .doubleLiteral,
      '1_2.3__4E-5_6': .doubleLiteral,
    };
    for (final entry in cases.entries) {
      test('preserves ${entry.key}', () {
        final result = scanText(entry.key);
        expect(result.hasErrors, isFalse);
        expect(result.tokens.map((t) => t.kind), <TokenKind>[
          entry.value,
          .eof,
        ]);
        expect(result.tokens.first.lexeme, entry.key);
        expect(result.tokens.first.length, entry.key.length);
      });
    }

    test('does not consume member access, cascades, or a leading sign', () {
      final result = scanText('1.foo 1..foo 1...x 1._name 1.e2 -2 +.5 0x1.foo');
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.lexeme), [
        '1',
        '.',
        'foo',
        '1',
        '..',
        'foo',
        '1',
        '...',
        'x',
        '1',
        '.',
        '_name',
        '1',
        '.',
        'e2',
        '-',
        '2',
        '+',
        '.5',
        '0x1',
        '.',
        'foo',
        '',
      ]);
    });

    for (final text in [
      '1_',
      '1__',
      '0x_1',
      '0x1_',
      '1_e2',
      '1e_2',
      '1.2_e3',
    ]) {
      test('diagnoses separators in $text and resumes at the next token', () {
        final result = scanText('$text; done');
        expect(
          result.diagnostics.single.code,
          'scanner.invalid_digit_separator',
        );
        expect(result.diagnostics.single.span!.text, matches(r'^_+$'));
        expect(result.tokens.map((t) => t.lexeme), [text, ';', 'done', '']);
      });
    }

    for (final text in ['0x', '0X']) {
      test('requires digits after $text', () {
        final result = scanText('$text; done');
        expect(result.diagnostics.single.code, 'scanner.missing_hex_digit');
        expect(result.tokens.map((t) => t.lexeme), [text, ';', 'done', '']);
      });
    }

    for (final text in ['1e', '1E+', '.5e-', '1.0e+']) {
      test('requires exponent digits in $text', () {
        final result = scanText('$text; done');
        expect(
          result.diagnostics.single.code,
          'scanner.missing_exponent_digit',
        );
        expect(result.tokens.map((t) => t.lexeme), [text, ';', 'done', '']);
      });
    }
  });
}
