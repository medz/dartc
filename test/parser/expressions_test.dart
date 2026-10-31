import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('parses every binary operator with written operands and ranges', () {
    for (final op in BinaryOperator.values) {
      final text = 'left ${op.spelling} right';
      final node = parsed(text) as BinaryExpression;
      expect(node.op, op);
      expect(node.left.text, 'left');
      expect(node.right.text, 'right');
      expect(node.text, text);
    }
  });

  test('preserves operator precedence and left associativity', () {
    expect(shape(parsed('a + b * c - d / e')), '(- (+ a (* b c)) (/ d e))');
    expect(shape(parsed('a - b - c')), '(- (- a b) c)');
    expect(shape(parsed('a ?? b ?? c')), '(?? (?? a b) c)');
    expect(
      shape(parsed('a ?? b || c && d == e < f | g ^ h & i << j + k * l')),
      '(?? a (|| b (&& c (== d (< e (| f (^ g (& h (<< i (+ j (* k l)))))))))))',
    );
    expect(shape(parsed('(a + b) * c')), '(* (group (+ a b)) c)');
    expect(shape(parsed('a < b == c < d')), '(== (< a b) (< c d))');
    expect(shape(parsed('a & b == c')), '(== (& a b) c)');
    expect(shape(parsed('a < b | c')), '(< a (| b c))');
  });

  test('parses right associative assignments without duplicating targets', () {
    for (final op in AssignmentOperator.values) {
      final node =
          parsed('target ${op.spelling} other = value') as AssignmentExpression;
      expect(node.op, op);
      expect(shape(node.right), '(= other value)');
    }
    final node = parsed('receiver()[key()] ??= fallback()');
    expect(
      walk(node).whereType<InvocationExpression>().map((e) => e.callee.text),
      ['receiver', 'key', 'fallback'],
    );
    expect(shape(parsed('a?.b = c')), '(= (?. a b) c)');
    expect(shape(parsed('a?[b] += c')), '(+= (?[] a b) c)');
  });

  test('keeps conditional branches and their assignments grouped', () {
    final cases = {
      'a ? b : c ? d : e': '(?: a b (?: c d e))',
      'a ? b ? c : d : e': '(?: a (?: b c d) e)',
      'a ? b = c : d = e': '(?: a (= b c) (= d e))',
      'a = b ? c : d = e': '(= a (?: b c (= d e)))',
      'a || b ? c + d : e * f': '(?: (|| a b) (+ c d) (* e f))',
      'f(a ? b : c, d)': '(call f (?: a b c) d)',
      'a ? (b?[i]) : c': '(?: a (group (?[] b i)) c)',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(shape(parsed(key)), value, reason: key);
    }
  });

  test('binds selectors before prefix operations and preserves updates', () {
    final cases = {
      '-a.b(1)[i]!': '(- (! ([] (call (. a b) 1) i)))',
      '!~ -a': '(! (~ (- a)))',
      '++this.value': '(pre++ (. this value))',
      'a?[key()]--': '(post-- (?[] a (call key)))',
      'a++!': '(! (post++ a))',
      '(a++).b': '(. (group (post++ a)) b)',
      'C.new': '(. C new)',
      'a?.b(c)?.d?[e]': '(?[] (?. (call (?. a b) c) d) e)',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(shape(parsed(key)), value, reason: key);
    }
  });

  test('keeps argument and record field order including named entries', () {
    expect(
      shape(parsed('f(name: a, b, other: c,)')),
      '(call f (name: a) b (other: c))',
    );
    expect(
      shape(parsed('(name: a, b, other: c,)')),
      '(record (name: a) b (other: c))',
    );
    expect(shape(parsed('()')), '(record)');
    expect(shape(parsed('(a,)')), '(record a)');
    expect(shape(parsed('(a)')), '(group a)');
    expect(shape(parsed('f()()')), '(call (call f))');
  });

  test('retains scalar spellings and adjacent plain strings', () {
    final kinds = {
      '123_456': LiteralKind.integer,
      '0xFf': LiteralKind.integer,
      '1.25e+3': LiteralKind.doubleLiteral,
      'true': LiteralKind.boolean,
      'false': LiteralKind.boolean,
      'null': LiteralKind.nullLiteral,
    };
    for (final MapEntry(:key, :value) in kinds.entries) {
      final node = parsed(key) as LiteralExpression;
      expect(node.kind, value);
      expect(node.text, key);
    }
    const text = "r'a\\b' /* gap */ '\\u{1f600}' '''more\ntext'''";
    final node = parsed(text) as AdjacentStringsExpression;
    expect(node.strings.map((s) => s.text), [
      "r'a\\b'",
      "'\\u{1f600}'",
      "'''more\ntext'''",
    ]);
    expect(node.text, text);
  });

  test(
    'allows built-in and contextual identifiers in synchronous expressions',
    () {
      for (final name in [
        'abstract',
        'as',
        'async',
        'await',
        'base',
        'covariant',
        'deferred',
        'dynamic',
        'export',
        'extension',
        'external',
        'factory',
        'Function',
        'get',
        'hide',
        'implements',
        'import',
        'interface',
        'late',
        'library',
        'mixin',
        'of',
        'on',
        'operator',
        'part',
        'required',
        'sealed',
        'set',
        'show',
        'static',
        'sync',
        'type',
        'typedef',
        'when',
        'yield',
      ]) {
        expect(parsed(name), isA<IdentifierExpression>(), reason: name);
      }
    },
  );

  test('uses the exact source snapshot and leaves scan results intact', () {
    final source = SourceFile(
      Uri.parse('memory:expression'),
      "/*😀*/ f('é', x: 1)",
    );
    final input = scan(source);
    final tokens = [...input.tokens];
    final comments = [...input.comments];
    final first = parseExpression(input);
    final second = parseExpression(input);
    expect(first.hasErrors, isFalse);
    expect(first.node.start, 7);
    expect(first.node.end, source.length);
    expect(walk(first.node).every((n) => identical(n.source, source)), isTrue);
    expect(input.tokens, orderedEquals(tokens));
    expect(input.comments, orderedEquals(comments));
    expect(identical(first.node, second.node), isFalse);
    expect(shape(first.node), shape(second.node));
    expect(() => first.diagnostics.clear(), throwsUnsupportedError);
  });

  test('handles deep expressions without using the Dart call stack', () {
    const depth = 12000;
    final cases = [
      '${'(' * depth}a${')' * depth}',
      '${'! ' * depth}a',
      '${'a = ' * depth}b',
      '${'a ? b : ' * depth}c',
      '${'a ? b : a?[i] ? c : ' * depth}d',
      '${'f(' * depth}a${')' * depth}',
      '${'a[' * depth}b${']' * depth}',
    ];
    for (final text in cases) {
      final node = parsed(text);
      expect(node.text, text);
      expect(walk(node).length, greaterThan(depth));
    }
  });
}
