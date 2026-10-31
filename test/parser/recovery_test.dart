import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('recovers missing operands with zero-width source nodes', () {
    final cases = {
      '': '<missing>',
      'a +': '(+ a <missing>)',
      'a ? : b': '(?: a <missing> b)',
      'a ? b :': '(?: a b <missing>)',
      'f(x:)': '(call f (x: <missing>))',
      'f(, a,,)': '(call f <missing> a <missing>)',
      'a[]': '([] a <missing>)',
      'a?[ ]': '(?[] a <missing>)',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      final result = parse(key);
      expect(result.hasErrors, isTrue, reason: key);
      expect(shape(result.node), value);
      expect(
        walk(result.node)
            .whereType<MissingExpression>()
            .every((n) => n.start == n.end),
        isTrue,
      );
    }
  });

  test('recovers unclosed groups and preserves later call arguments', () {
    final cases = {
      'f(a +, b)': '(call f (+ a <missing>) b)',
      'f(a[b)': '(call f ([] a b))',
      'a[(b]': '([] a (group b))',
      'f((a': '(call f (group a))',
      'a ? b': '(?: a b <missing>)',
      'f(a ? b, c)': '(call f (?: a b <missing>) c)',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      final result = parse(key);
      expect(result.hasErrors, isTrue, reason: key);
      expect(shape(result.node), value, reason: key);
      expect(result.node.text, key);
    }
  });

  test('reports invalid comparison chains and assignment target forms', () {
    for (final text in [
      'a < b < c',
      'a == b != c',
      'a > b >= c',
      '1 = 2',
      'a + b += c',
      'f()++',
      '++(a)',
      'a! = b',
      '++a++',
      'a++.b',
      'a++()',
      'a++[b]',
      'a++!.b',
      'a++!()',
      'a++![b]',
      '+a',
      'a b',
      'a;',
      ')',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    expect(parse('(a < b) == (c > d)').hasErrors, isFalse);
  });

  test(
    'diagnoses grammar that is not implemented instead of accepting a prefix',
    () {
      for (final text in [
        '(a) = b',
        '[a]',
        '{a: b}',
        '#name',
        'new C()',
        'const C()',
        'a as T',
        'a is T',
        'f<T>()',
        'a..b()',
        r'"$a"',
        'throw a',
        'super.x',
        '.new()',
        '() => a',
        'switch (a) { _ => b }',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      expect(
        parse('(a) = b').diagnostics.single.code,
        'parser.unsupported_syntax',
      );
    },
  );

  test('reports the pending list and conditional disambiguation', () {
    for (final text in ['a ? b?[i] : c', 'a ? b?[i]++ : c']) {
      expect(
        parse(text).diagnostics.map((d) => d.code),
        contains('parser.unsupported_syntax'),
      );
    }
  });

  test('retains lexical diagnostics and immutable error snapshots', () {
    final input = scan(SourceFile(Uri.parse('memory:error'), 'a + `'));
    final result = parseExpression(input);
    expect(result.hasErrors, isTrue);
    expect(result.diagnostics.first, same(input.diagnostics.first));
    expect(result.diagnostics.last.code, 'parser.expected_expression');
    final before = [...result.diagnostics];
    parse('f(');
    expect(result.diagnostics, orderedEquals(before));
    expect(() => result.diagnostics.clear(), throwsUnsupportedError);
    for (final diagnostic in result.diagnostics) {
      expect(diagnostic.span!.source, same(input.source));
    }
  });

  test(
    'recovers malformed token sequences without throwing or mutating input',
    () {
      final random = Random(7149);
      const fragments = [
        'a',
        '1',
        '+',
        '-',
        '*',
        '=',
        '??=',
        '++',
        '!',
        '?',
        ':',
        ',',
        '(',
        ')',
        '[',
        ']',
        '.',
        '?.',
        '[]',
        '[]=',
        '"x"',
        '{',
        '}',
        'class',
        'as',
        'new',
        r'"$x"',
        ';',
        '`',
      ];
      for (var i = 0; i < 1200; i++) {
        final text = [
          for (var n = random.nextInt(30); n > 0; n--)
            fragments[random.nextInt(fragments.length)],
        ].join(' ');
        final input = scan(SourceFile(Uri.parse('memory:fuzz'), text));
        final tokens = [...input.tokens];
        final result = parseExpression(input);
        expect(input.tokens, orderedEquals(tokens), reason: text);
        for (final node in walk(result.node)) {
          expect(node.source, same(input.source));
          expect(node.start, inInclusiveRange(0, text.length), reason: text);
          expect(
            node.end,
            inInclusiveRange(node.start, text.length),
            reason: text,
          );
        }
      }
    },
  );
}
