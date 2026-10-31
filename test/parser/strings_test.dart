import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('preserves text, empty segments, delimiters and UTF-16 ranges', () {
    const text = r'"😀\n$a$b ${f<int>(x, named: y)}!"';
    final node = parsed(text) as InterpolatedStringExpression;
    expect(node.text, text);
    expect(node.parts.map((p) => p.text), [
      r'"😀\n',
      r'$a',
      '',
      r'$b',
      ' ',
      r'${f<int>(x, named: y)}',
      '!"',
    ]);
    expect(node.parts.map((p) => p.text).join(), text);
    expect(node.parts.first.end, 5);
    final first = node.parts[1] as StringInterpolation;
    expect(first.isBraced, isFalse);
    expect(first.expression.text, 'a');
    expect(first.expression.start, 6);
    final call = node.parts[5] as StringInterpolation;
    expect(call.isBraced, isTrue);
    expect(call.expression, isA<InvocationExpression>());
    expect(
      (call.expression as InvocationExpression).typeArguments!.text,
      '<int>',
    );
    expect(() => node.parts.clear(), throwsUnsupportedError);
  });

  test('accepts this and identifiers in unbraced interpolations', () {
    for (final name in [
      'a',
      '_name',
      'this',
      'await',
      'yield',
      'type',
      'get',
    ]) {
      final node = parsed('"\$$name"') as InterpolatedStringExpression;
      final part = node.parts[1] as StringInterpolation;
      expect(part.isBraced, isFalse);
      expect(part.expression.text, name);
      expect(
        part.expression,
        name == 'this' ? isA<ThisExpression>() : isA<IdentifierExpression>(),
      );
    }
    final node = parsed(r'"$a.b()"') as InterpolatedStringExpression;
    expect((node.parts[1] as StringInterpolation).expression.text, 'a');
    expect(node.parts.last.text, '.b()"');
  });

  test('rejects reserved words after an unbraced dollar', () {
    for (final name in [
      'true',
      'false',
      'null',
      'new',
      'super',
      'return',
      'if',
    ]) {
      final result = parse('"\$$name"');
      expect(result.diagnostics.map((d) => d.code), [
        'parser.expected_identifier',
      ], reason: name);
      final node = result.node as InterpolatedStringExpression;
      expect(
        (node.parts[1] as StringInterpolation).expression,
        isA<MissingExpression>(),
      );
      expect(node.parts.map((p) => p.text).join(), '"\$$name"');
    }
  });

  test('joins plain, raw and interpolated strings across trivia', () {
    const text = r'''"a" /* comment */ '$b' r"$raw" "${c}"''';
    final node = parsed(text) as AdjacentStringsExpression;
    expect(node.text, text);
    expect(node.strings.map((s) => s.text), [
      '"a"',
      r"'$b'",
      r'r"$raw"',
      r'"${c}"',
    ]);
    expect(node.strings[0], isA<StringLiteralExpression>());
    expect(node.strings[1], isA<InterpolatedStringExpression>());
    expect(node.strings[2], isA<StringLiteralExpression>());
    expect(node.strings[3], isA<InterpolatedStringExpression>());
    expect(() => node.strings.clear(), throwsUnsupportedError);
  });

  test('retains multiline whitespace, escapes and line endings', () {
    const text = '"""\r\n  \${x}\\n\r\n"""';
    final node = parsed(text) as InterpolatedStringExpression;
    expect(node.parts.map((p) => p.text), ['"""\r\n  ', r'${x}', '\\n\r\n"""']);
    expect(parsed(r'r"$a ${b}"'), isA<StringLiteralExpression>());
    expect(parsed(r'"\$a \u0024b"'), isA<StringLiteralExpression>());
  });

  test('parses embedded expressions and resumes their surrounding context', () {
    final cases = {
      'a + b * c': '(+ a (* b c))',
      'a ? [b] : c': '(?: a (list b) c)',
      'a[b]?[c]?[d] : e': '(?: (?[] ([] a b) c) (list d) e)',
      'a?[b]': '(?[] a b)',
      'f(x, name: y)': '(call f x (name: y))',
      '(x, name: y)': '(record x (name: y))',
      '[if (ok) a else b]': '(list (if ok a b))',
      '{"k": value}': '(braces (: "k" value))',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      final node = parsed('"\${$key}"') as InterpolatedStringExpression;
      expect(shape((node.parts[1] as StringInterpolation).expression), value);
    }
    final call = parsed(r'f("${a + b}", x) + y') as BinaryExpression;
    expect(call.right.text, 'y');
    expect(
      (call.left as InvocationExpression).arguments.arguments.last.text,
      'x',
    );
    final conditional = parsed(r'a ? ["$b"] : c') as ConditionalExpression;
    expect(conditional.thenExpression, isA<CollectionExpression>());
    final index = parsed(r'a?["$b"]') as IndexExpression;
    expect(index.index, isA<InterpolatedStringExpression>());
    final cast = parsed(r'"${a as T?}"') as InterpolatedStringExpression;
    expect(
      ((cast.parts[1] as StringInterpolation).expression as CastExpression)
          .type
          .isNullable,
      isTrue,
    );
    final typeTest = parsed(r'"${a is T?}"') as InterpolatedStringExpression;
    expect(
      ((typeTest.parts[1] as StringInterpolation).expression
              as TypeTestExpression)
          .type
          .isNullable,
      isTrue,
    );
    final generic = parsed(r'"${f<T>}"') as InterpolatedStringExpression;
    expect(
      (generic.parts[1] as StringInterpolation).expression,
      isA<TypeInstantiationExpression>(),
    );
  });

  test('keeps nested interpolation and adjacent literal boundaries', () {
    const text = r'''"${"$a" r'$b'}${"${c}"}"''';
    final node = parsed(text) as InterpolatedStringExpression;
    expect(node.parts.map((p) => p.text).join(), text);
    final adjacent =
        (node.parts[1] as StringInterpolation).expression
            as AdjacentStringsExpression;
    expect(adjacent.strings, hasLength(2));
    expect(adjacent.strings.first, isA<InterpolatedStringExpression>());
    expect(adjacent.strings.last, isA<StringLiteralExpression>());
    final nested =
        (node.parts[3] as StringInterpolation).expression
            as InterpolatedStringExpression;
    expect((nested.parts[1] as StringInterpolation).expression.text, 'c');
  });

  test('recovers missing expressions and closers before later arguments', () {
    for (final text in [r'f("${}", x)', r'f("${(a}", x)', r'f("${a[1}", x)']) {
      final result = parse(text);
      expect(result.hasErrors, isTrue, reason: text);
      final call = result.node as InvocationExpression;
      expect(call.arguments.arguments.last.text, 'x');
      expect(
        call.arguments.arguments.first.value,
        isA<InterpolatedStringExpression>(),
      );
      expect(result.node.text, text);
    }
    final empty = parse(r'"${}"').node as InterpolatedStringExpression;
    final missing = (empty.parts[1] as StringInterpolation).expression;
    expect(missing, isA<MissingExpression>());
    expect(missing.start, 3);
    expect(missing.end, 3);
  });

  test('retains unclosed interpolations without inventing source text', () {
    for (final text in [r'"${', r'"${a', r'"${"${1', r'"$a']) {
      final result = parse(text);
      expect(result.hasErrors, isTrue);
      expect(result.node.text, text);
      for (final node in walk(result.node)) {
        expect(node.start, inInclusiveRange(0, text.length));
        expect(node.end, inInclusiveRange(node.start, text.length));
      }
      final node = result.node as InterpolatedStringExpression;
      expect(node.parts.map((p) => p.text).join(), text);
    }
  });

  test('handles deep nesting and long adjacency without recursive parsing', () {
    const depth = 12000;
    final text = '${r'"${' * depth}1${r'}"' * depth}';
    final node = parsed(text);
    expect(walk(node).whereType<StringInterpolation>().length, depth);
    expect(node.text, text);
    final adjacent =
        parsed('${r'"$a" ' * depth}"b"') as AdjacentStringsExpression;
    expect(adjacent.strings, hasLength(depth + 1));
    final incomplete = parse('${r'"${' * depth}1');
    expect(incomplete.hasErrors, isTrue);
    expect(
      walk(incomplete.node).whereType<StringInterpolation>().length,
      depth,
    );
  });

  test('preserves scanner snapshots through conditional trials in strings', () {
    final input = scan(
      SourceFile(Uri.parse('memory:strings'), r'"${a[b]?[c]?[d] : e}"'),
    );
    final before = input.tokens
        .map((t) => (t.kind, t.start, t.end, t.lexeme))
        .toList();
    for (var i = 0; i < 2; i++) {
      final result = parseExpression(input);
      expect(result.hasErrors, isFalse);
      expect(
        walk(result.node).every((n) => identical(n.source, input.source)),
        isTrue,
      );
    }
    expect(input.tokens.map((t) => (t.kind, t.start, t.end, t.lexeme)), before);
  });

  test('malformed strings keep nodes and diagnostics within the snapshot', () {
    final random = Random(11507);
    const fragments = [
      r'"${',
      r'"$',
      r'$a',
      r'${',
      '}',
      '"',
      "'",
      r'\',
      'a',
      '1',
      '(',
      ')',
      '[',
      ']',
      '{',
      '?',
      ':',
      ',',
      '+',
      'is',
      'T?',
      '\n',
    ];
    for (var i = 0; i < 1500; i++) {
      final text = List.generate(
        random.nextInt(28),
        (_) => fragments[random.nextInt(fragments.length)],
      ).join();
      final input = scan(SourceFile(Uri.parse('memory:malformed'), text));
      final result = parseExpression(input);
      for (final node in walk(result.node)) {
        expect(node.source, same(input.source));
        expect(node.start, inInclusiveRange(0, text.length));
        expect(node.end, inInclusiveRange(node.start, text.length));
      }
      for (final diagnostic in result.diagnostics) {
        expect(diagnostic.span!.source, same(input.source));
      }
    }
  });
}
