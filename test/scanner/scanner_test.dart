import 'dart:math';

import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ScanResult scanText(String text) =>
    scan(SourceFile(Uri.parse('memory:test.dart'), text));

void main() {
  group('scan', () {
    test('returns one EOF and preserves the source snapshot', () {
      for (final text in ['', ' \t\r\n', 'final answer = 42;']) {
        final source = SourceFile(Uri.parse('memory:test.dart'), text);
        final result = scan(source);
        expect(result.source, same(source));
        expect(result.hasErrors, isFalse);
        expect(
          result.tokens.where((token) => token.kind == .eof),
          hasLength(1),
        );
        expect(result.tokens.last.start, text.length);
        expect(result.tokens.last.end, text.length);
        for (final token in result.tokens) {
          expect(token.source, same(source));
          expect(token.lexeme, text.substring(token.start, token.end));
        }
      }
    });

    test('recognizes every stable keyword and keeps neighboring names intact', () {
      const words =
          'abstract as assert async await base break case catch class '
          'const continue covariant default deferred do dynamic else enum export '
          'extends extension external factory false final finally for Function get '
          'hide if implements import in interface is late library mixin new null '
          'of on operator part required rethrow return sealed set show static '
          'super switch sync this throw true try type typedef var void when while '
          'with yield';
      final result = scanText(words);
      expect(result.hasErrors, isFalse);
      expect(
        result.tokens.take(result.tokens.length - 1).map((t) => t.lexeme),
        words.split(' '),
      );
      for (final token in result.tokens.take(result.tokens.length - 1)) {
        expect(token.kind.isKeyword, isTrue, reason: token.lexeme);
        expect(token.kind.spelling, token.lexeme);
      }
      final names = scanText(r'ifx _if $if if$ Function2 function R r');
      expect(names.hasErrors, isFalse);
      expect(
        names.tokens.take(names.tokens.length - 1).map((t) => t.kind),
        everyElement(TokenKind.identifier),
      );
    });

    test('takes the longest punctuation token', () {
      const cases = <String, TokenKind>{
        '(': .leftParen,
        ')': .rightParen,
        '[': .leftBracket,
        ']': .rightBracket,
        '[]': .emptyBrackets,
        '[]=': .emptyBracketsAssign,
        '{': .leftBrace,
        '}': .rightBrace,
        ',': .comma,
        ':': .colon,
        ';': .semicolon,
        '@': .at,
        '#': .hash,
        '.': .dot,
        '..': .cascade,
        '...': .spread,
        '...?': .nullAwareSpread,
        '?': .question,
        '?.': .nullAwareAccess,
        '?..': .nullAwareCascade,
        '??': .ifNull,
        '??=': .ifNullAssign,
        '=': .assign,
        '==': .equal,
        '=>': .arrow,
        '!': .bang,
        '!=': .notEqual,
        '+': .plus,
        '++': .increment,
        '+=': .plusAssign,
        '-': .minus,
        '--': .decrement,
        '-=': .minusAssign,
        '*': .star,
        '*=': .starAssign,
        '/': .slash,
        '/=': .slashAssign,
        '%': .percent,
        '%=': .percentAssign,
        '~': .tilde,
        '~/': .truncateDivide,
        '~/=': .truncateDivideAssign,
        '&': .ampersand,
        '&&': .logicalAnd,
        '&=': .andAssign,
        '|': .bar,
        '||': .logicalOr,
        '|=': .orAssign,
        '^': .caret,
        '^=': .xorAssign,
        '<': .less,
        '<=': .lessEqual,
        '<<': .shiftLeft,
        '<<=': .shiftLeftAssign,
        '>': .greater,
        '>=': .greaterEqual,
        '>>': .shiftRight,
        '>>=': .shiftRightAssign,
        '>>>': .unsignedShiftRight,
        '>>>=': .unsignedShiftRightAssign,
      };
      final result = scanText(cases.keys.join(' '));
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.kind), <TokenKind>[
        ...cases.values,
        .eof,
      ]);
      expect(result.tokens.map((t) => t.lexeme), [...cases.keys, '']);
      expect(
        scanText('>>>=>>> >>=>> >=><<=<< <=<').tokens.map((t) => t.lexeme),
        ['>>>=', '>>>', '>>=', '>>', '>=', '>', '<<=', '<<', '<=', '<', ''],
      );
    });

    test('keeps adjacent index operators distinct from spaced brackets', () {
      final result = scanText('[] []= [ ] [/* gap */]');
      expect(result.hasErrors, isFalse);
      expect(result.tokens.map((t) => t.kind), <TokenKind>[
        .emptyBrackets,
        .emptyBracketsAssign,
        .leftBracket,
        .rightBracket,
        .leftBracket,
        .rightBracket,
        .eof,
      ]);
    });

    test(
      'leaves bracket matching and keyword position rules to the parser',
      () {
        final result = scanText(') ] } ( [ { final if = 0;');
        expect(result.hasErrors, isFalse);
        expect(result.tokens.map((t) => t.kind), <TokenKind>[
          .rightParen,
          .rightBracket,
          .rightBrace,
          .leftParen,
          .leftBracket,
          .leftBrace,
          .keywordFinal,
          .keywordIf,
          .assign,
          .integer,
          .semicolon,
          .eof,
        ]);
      },
    );

    test(
      'preserves comments separately, including nested and doc comments',
      () {
        const text =
            'a// one\r\n/// docs\r/* outer /* inner */ end */b/** docs */';
        final result = scanText(text);
        expect(result.hasErrors, isFalse);
        expect(result.tokens.map((t) => t.lexeme), ['a', 'b', '']);
        expect(result.comments.map((t) => t.lexeme), [
          '// one',
          '/// docs',
          '/* outer /* inner */ end */',
          '/** docs */',
        ]);
        expect(result.comments.map((t) => t.kind), <TokenKind>[
          .lineComment,
          .lineComment,
          .blockComment,
          .blockComment,
        ]);
        for (final comment in result.comments) {
          expect(comment.source, same(result.source));
          expect(comment.lexeme, text.substring(comment.start, comment.end));
        }
      },
    );

    test('handles BOM and script tags only in their allowed positions', () {
      final bom = scanText('\uFEFFx');
      expect(bom.hasErrors, isFalse);
      expect(bom.tokens.first.start, 1);
      final script = scanText('#!/usr/bin/env dart\r\nvoid main() {}');
      expect(script.tokens.first.kind, TokenKind.scriptTag);
      expect(script.tokens.first.lexeme, '#!/usr/bin/env dart');
      expect(script.tokens[1].start, 21);
      expect(scanText('\uFEFF#!dart').tokens.first.kind, TokenKind.hash);
      expect(scanText(' #!dart').tokens.first.kind, TokenKind.hash);
      expect(
        scanText('x\uFEFF').diagnostics.single.code,
        'scanner.unexpected_character',
      );
    });

    test('retains invalid characters and continues after them', () {
      final result = scanText('a\u{1F600}\u00A0\uD800\u0000\u000C b');
      expect(result.tokens.map((t) => t.kind), <TokenKind>[
        .identifier,
        .invalid,
        .invalid,
        .invalid,
        .invalid,
        .invalid,
        .identifier,
        .eof,
      ]);
      expect(result.diagnostics, hasLength(5));
      expect(
        result.diagnostics.map((d) => d.code),
        everyElement('scanner.unexpected_character'),
      );
      expect(result.tokens[1].length, 2);
      expect(result.diagnostics.first.span, result.tokens[1].span);
      expect(result.tokens[result.tokens.length - 2].lexeme, 'b');
    });

    test('reports an unterminated nested comment at its source range', () {
      final result = scanText('a /* outer /* inner */');
      expect(result.tokens.map((t) => t.lexeme), ['a', '']);
      expect(result.comments.single.lexeme, '/* outer /* inner */');
      expect(result.diagnostics.single.code, 'scanner.unterminated_comment');
      expect(result.diagnostics.single.span, result.comments.single.span);
    });

    test('nested block comments use bounded call depth', () {
      final text =
          '${List.filled(10000, '/*').join()} body '
          '${List.filled(10000, '*/').join()}next';
      final result = scanText(text);
      expect(result.hasErrors, isFalse);
      expect(result.comments.single.end, text.length - 4);
      expect(result.tokens.map((t) => t.lexeme), ['next', '']);
    });

    test('does not share mutable results between scans', () {
      final first = scanText('/* comment */ `');
      final next = scanText('ok');
      expect(next.hasErrors, isFalse);
      expect(next.comments, isEmpty);
      expect(first.diagnostics, hasLength(1));
      expect(() => first.tokens.clear(), throwsUnsupportedError);
      expect(() => first.comments.clear(), throwsUnsupportedError);
      expect(() => first.diagnostics.clear(), throwsUnsupportedError);
    });

    test(
      'terminates on malformed input and keeps every reported range valid',
      () {
        final random = Random(7351);
        const alphabet = 'ar0x1e_\$\'"\\{}[]()/ *\r\n!?\uD800\uDC00';
        for (var i = 0; i < 1000; i++) {
          final text = String.fromCharCodes([
            for (var n = random.nextInt(80); n > 0; n--)
              alphabet.codeUnitAt(random.nextInt(alphabet.length)),
          ]);
          final result = scanText(text);
          var end = 0;
          for (final token in result.tokens) {
            expect(token.start, greaterThanOrEqualTo(end), reason: text);
            expect(token.end, lessThanOrEqualTo(text.length), reason: text);
            expect(token.end, greaterThanOrEqualTo(token.start), reason: text);
            end = token.end;
          }
          expect(result.tokens.last.kind, TokenKind.eof);
          expect(end, text.length);
          for (final diagnostic in result.diagnostics) {
            expect(diagnostic.span!.source, same(result.source));
            expect(diagnostic.span!.end, lessThanOrEqualTo(text.length));
          }
        }
      },
    );
  });
}
