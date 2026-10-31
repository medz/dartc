import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'parses collection elements and leaves brace classification unresolved',
    () {
      final cases = {
        '[]': '(list)',
        '[ ]': '(list)',
        '{}': '(braces)',
        '[a, b + c,]': '(list a (+ b c))',
        '{a, b}': '(braces a b)',
        '{a: b, c: d,}': '(braces (: a b) (: c d))',
        '[...a, ...?b, ?c]': '(list (... a) (...? b) (? c))',
        '{?a: ?b, c: ?d, ?e: f}': '(braces (?:? a b) (:? c d) (?: e f))',
        '{a ? b : c: d ? e : f}': '(braces (: (?: a b c) (?: d e f)))',
        '[if (a) b else c]': '(list (if a b c))',
        '[if (a) if (b) c else d else e]': '(list (if a (if b c d) e))',
        '[if (a) ...b, if (c) ?d]': '(list (if a (... b)) (if c (? d)))',
        '{if (a) ?b: ?c else d: e}': '(braces (if a (?:? b c) (: d e)))',
        '[[a], {b: c}][0]': '([] (list (list a) (braces (: b c))) 0)',
        '[for (;;) a]': '(list (for (parts) a))',
        '[for (x in xs) if (x) x]': '(list (for (in x xs) (if x x)))',
        '[if (a) for (var x in xs) x else b]':
            '(list (if a (for (in (varKeyword x) xs) x) b))',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(shape(parsed(key)), value, reason: key);
      }
    },
  );

  test('preserves explicit const and nested collection types and ranges', () {
    for (final text in ['const <List<int>>[]', '<String, List<int>>{a: b}']) {
      final node = parsed(text) as CollectionExpression;
      expect(node.text, text);
      expect(node.hasConstKeyword, text.startsWith('const'));
      expect(
        node.typeArguments!.arguments.length,
        text.contains('String') ? 2 : 1,
      );
      expect(
        node.typeArguments!.text,
        text.contains('String') ? '<String, List<int>>' : '<List<int>>',
      );
    }
    expect(
      (parsed('const {}') as CollectionExpression).hasConstKeyword,
      isTrue,
    );
    expect((parsed('[]') as CollectionExpression).typeArguments, isNull);
  });

  test(
    'retains declaration modifiers, initializer order, and missing loop parts',
    () {
      final node = parsed(
        '[for (final int i = 0, j = 1; i < n; i++, j += 2,) i]',
      ) as CollectionExpression;
      final loop = node.elements.single as ForElement;
      final parts = loop.parts as ForParts;
      final declarations = parts.initializer as VariableDeclarationList;
      expect(declarations.keyword, VariableKeyword.finalKeyword);
      expect(declarations.isLate, isFalse);
      expect(declarations.type!.text, 'int');
      expect(declarations.declarations.map((d) => d.text), ['i = 0', 'j = 1']);
      expect(parts.condition!.text, 'i < n');
      expect(parts.updaters.map((e) => e.text), ['i++', 'j += 2']);
      expect(parts.text, 'final int i = 0, j = 1; i < n; i++, j += 2');
      final empty =
          ((parsed('[for ( ; ; ) x]') as CollectionExpression).elements.single
                      as ForElement)
                  .parts
              as ForParts;
      expect(empty.initializer, isNull);
      expect(empty.condition, isNull);
      expect(empty.updaters, isEmpty);
      expect(empty.text, '; ;');
      final assignment =
          ((parsed('[for (i = 0;;) i]') as CollectionExpression).elements.single
                      as ForElement)
                  .parts
              as ForParts;
      expect(assignment.initializer, isA<AssignmentExpression>());
      final cast =
          ((parsed(
                        '[for (value as T;;) x]',
                      ) as CollectionExpression).elements.single
                      as ForElement)
                  .parts
              as ForParts;
      expect(cast.initializer, isA<CastExpression>());
      final keyword =
          ((parsed(
                        '[for (late=0; late<2; late++) late]',
                      ) as CollectionExpression).elements.single
                      as ForElement)
                  .parts
              as ForParts;
      expect(keyword.initializer!.text, 'late=0');
      for (final condition in ['T', 'p.T', '(T,)']) {
        final parts =
            ((parsed(
                          '[for ($condition? x=a:b;;) x]',
                        ) as CollectionExpression).elements.single
                        as ForElement)
                    .parts
                as ForParts;
        expect(parts.initializer, isA<ConditionalExpression>());
      }
      final nullable =
          ((parsed(
                        '[for (T? x=a;;) x]',
                      ) as CollectionExpression).elements.single
                      as ForElement)
                  .parts
              as ForParts;
      expect(nullable.initializer, isA<VariableDeclarationList>());
    },
  );

  test('retains for-in target syntax without resolving or rewriting it', () {
    for (final text in [
      'final x',
      'final List<int> x',
      '(int, String) x',
      'var x',
      'const x',
      'final late',
      'late',
      'Function',
      'x',
    ]) {
      final loop =
          (parsed(
                '[for ($text in values) x]',
              ) as CollectionExpression).elements.single
              as ForElement;
      final parts = loop.parts as ForInParts;
      expect(parts.target.text, text);
      expect(parts.iterable.text, 'values');
      expect(parts.text, '$text in values');
    }
  });

  test('prefers valid conditional branches over null-aware indexing', () {
    final cases = {
      'a?[i] : c': '(?: a (list i) c)',
      'a?[] : c': '(?: a (list) c)',
      'a?[i] + b': '(+ (?[] a i) b)',
      'a?[i] ? b : c': '(?: (?[] a i) b c)',
      'a ? (b?[i]) : c': '(?: a (group (?[] b i)) c)',
      'a?[i] : b = c': '(?: a (list i) (= b c))',
      'a?[i] + b?[j] : c': '(?: (+ (?[] a i) b) (list j) c)',
      'a?[i] ? b : a?[i]?[j] : c': '(?: a (?: (list i) b (?[] (?[] a i) j)) c)',
      '[a?[i], b?[j] : c]': '(list (?[] a i) (?: b (list j) c))',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(shape(parsed(key)), value, reason: key);
    }
    expect(parse('a ? b?[i] : c').hasErrors, isTrue);
    expect(parse('a ? b?[i]++ : c').hasErrors, isTrue);
    expect(parse('a?[i]?[j] : c').hasErrors, isTrue);
    expect(parse('f(x)?[i]?[j] : c').hasErrors, isTrue);
    expect(parse('a?[i] :').hasErrors, isTrue);
  });

  test('diagnoses invalid elements, headers, and remaining grammar gaps', () {
    for (final text in [
      '[,]',
      '[a,,b]',
      '[1: 2]',
      '[...?]',
      '{...a: b}',
      '{a: ...b}',
      '{a:}',
      '[if (a)]',
      '[if (a) b else]',
      '[else a]',
      '[for (x) x]',
      '[for (i=0, j=0;;) i]',
      '[for (;;,) i]',
      '[for (;;i++,,) i]',
      '[for (var x = 1 in xs) x]',
      '[for (var x,y in xs) x]',
      '[for (a.b in xs) x]',
      '[for (late var x in xs) x]',
      '[for (late final int i=0;;) i]',
      '[await for (x in xs) x]',
      '[if (a case var b) b]',
      '[for (var (a,b) in xs) a]',
      '[?.x]',
      '{a: ?.x}',
      '[]=a',
      'a[]=b',
      '[if (a) (b) else {}]',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test(
    'handles deeply nested collections, controls, and ambiguous indexes',
    () {
      const depth = 12000;
      for (final text in [
        '${'[' * depth}a${']' * depth}',
        '[${'if (a) ' * depth}b]',
        '[${'for (;;) ' * depth}a]',
        '${'[for (T? x=' * depth}a${': b;;) x]' * depth}',
        '${'a?[i] + ' * depth}b?[j] : c',
        '${'a ? b : a?[i] ? c : ' * depth}d',
      ]) {
        final node = parsed(text);
        expect(walk(node).length, greaterThan(depth));
        expect(node.text, text);
      }
      final invalid = parse('${'a?[i] + ' * depth}b?[j] :');
      expect(invalid.hasErrors, isTrue);
      expect(walk(invalid.node).length, greaterThan(depth));
    },
  );

  test(
    'recovers malformed elements without mutating tokens or escaping ranges',
    () {
      final random = Random(3827);
      const fragments = [
        'a',
        '1',
        '[',
        ']',
        '{',
        '}',
        '(',
        ')',
        'if',
        'else',
        'for',
        'in',
        'var',
        'final',
        'late',
        'const',
        '<',
        '>',
        '=',
        ';',
        ',',
        ':',
        '?',
        '...',
        '...?',
        '+',
        '++',
        '[]',
        '[]=',
      ];
      for (var i = 0; i < 1500; i++) {
        final text = [
          for (var n = random.nextInt(35); n > 0; n--)
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
