import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('keeps one cascade receiver and ordered sections', () {
    final node =
        parsed('make()..x = f()..run(y)..[i] += z') as CascadeExpression;
    expect(node.target.text, 'make()');
    expect(node.sections.map((s) => s.text), [
      '..x = f()',
      '..run(y)',
      '..[i] += z',
    ]);
    expect(node.isNullAware, isFalse);
    expect(walk(node).whereType<Identifier>().map((n) => n.text), [
      'make',
      'x',
      'f',
      'run',
      'y',
      'i',
      'z',
    ]);
    expect(() => node.sections.clear(), throwsUnsupportedError);
    expect(
      shape(node),
      '(cascade (call make) (= (.. x) (call f)) (call (.. run) y) (+= (..[] i) z))',
    );
  });

  test(
    'separates cascade receivers from outer assignments and branch values',
    () {
      for (final MapEntry(:key, :value) in {
        'a = b..c': '(= a (cascade b (.. c)))',
        'a + b..c': '(cascade (+ a b) (.. c))',
        'a ? b : c..d': '(cascade (?: a b c) (.. d))',
        'a = b ? c : d = e..f': '(= a (cascade (?: b c (= d e)) (.. f)))',
        'a..b = c ? d : e..f': '(cascade a (= (.. b) (?: c d e)) (.. f))',
        'a..b = c = d..e': '(cascade a (= (.. b) (= c d)) (.. e))',
        'a..b = (c..d)..e':
            '(cascade a (= (.. b) (group (cascade c (.. d)))) (.. e))',
        '(a..b).c': '(. (group (cascade a (.. b))) c)',
        '-a..b': '(cascade (- a) (.. b))',
      }.entries) {
        expect(shape(parsed(key)), value, reason: key);
      }
    },
  );

  test('retains null-aware cascades and selectors independently', () {
    final node =
        parsed('items?..[key()]?[next()]..child?.run()') as CascadeExpression;
    expect(node.isNullAware, isTrue);
    final index = node.sections.first as IndexExpression;
    expect(index.isNullAware, isTrue);
    expect(index.target, isA<CascadeIndexExpression>());
    expect(index.target.text, '?..[key()]');
    final call = node.sections.last as InvocationExpression;
    expect((call.callee as PropertyAccessExpression).isNullAware, isTrue);
    final generic = parsed('a..run<T>(x)..new()') as CascadeExpression;
    expect(
      (generic.sections.first as InvocationExpression).typeArguments!.text,
      '<T>',
    );
    expect(
      (generic.sections.last as InvocationExpression).callee.text,
      '..new',
    );
    expect(parsed('a..x!!.y'), isA<CascadeExpression>());
  });

  test('rejects unsupported continuations of unparenthesized cascades', () {
    for (final text in [
      'a..b?..c',
      'a..b++',
      'a..b--',
      'a..b + c',
      'a..b as T',
      'a..b ? c : d',
      'a..b?[i] : d',
      'a ? b..c : d',
      'a..[i]?[j]?[k] : d',
      'a..b() = c',
      'super..x',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test(
    'wraps the complete shorthand selector chain before outer operations',
    () {
      for (final text in [
        '.a',
        '.new',
        '.a().b?.c()[i]!',
        '.a<T>()',
        '.a<T>',
        '.a!.b',
        '.a!<T>()',
      ]) {
        final node = parsed(text) as DotShorthandExpression;
        expect(node.text, text);
        expect(
          walk(node)
              .whereType<DotShorthandReferenceExpression>()
              .single
              .name
              .text,
          text.startsWith('.new') ? 'new' : 'a',
        );
      }
      for (final MapEntry(:key, :value) in {
        '-.a': '(- (context (dot a)))',
        '.a + b': '(+ (context (dot a)) b)',
        '.a ? b : c': '(?: (context (dot a)) b c)',
        '.a..b': '(cascade (context (dot a)) (.. b))',
        '(.a).b': '(. (group (context (dot a))) b)',
        '.a!!': '(! (context (! (dot a))))',
        '.a!!.b': '(. (! (context (! (dot a)))) b)',
        '.a().b++': '(post++ (context (. (call (dot a)) b)))',
        '.a().b = x': '(= (context (. (call (dot a)) b)) x)',
      }.entries) {
        expect(shape(parsed(key)), value, reason: key);
      }
      for (final text in ['.a++', '.a = x', '++ .a']) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
    },
  );

  test(
    'retains explicit const shorthand syntax and null-assertion boundaries',
    () {
      final value =
          parsed('const .named<T>(x, flag: y)') as DotShorthandExpression;
      final head = value.expression as ConstDotShorthandExpression;
      expect(head.name.text, 'named');
      expect(head.typeArguments!.text, '<T>');
      expect(head.arguments!.arguments.map((n) => n.text), ['x', 'flag: y']);
      expect(head.childCount, 3);
      expect(head.childAt(1), same(head.typeArguments));
      expect(head.childAt(2), same(head.arguments));
      final asserted = parsed('const .new()!') as NullAssertionExpression;
      expect(asserted.operand, isA<DotShorthandExpression>());
      expect(asserted.operand.text, 'const .new()');
      final selected = parsed('const .new()!.x') as DotShorthandExpression;
      expect(selected.expression, isA<PropertyAccessExpression>());
      for (final text in [
        'const .()',
        '.',
        '.if',
        'const .new()!!.x',
        'const .new()!! ? a : b',
        'const .new()!<T>()',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      for (final text in ['const .x', 'const .new', 'const .f<T>']) {
        final reference =
            (parsed(text) as DotShorthandExpression).expression
                as ConstDotShorthandExpression;
        expect(reference.arguments, isNull);
        expect(reference.text, text);
      }
    },
  );

  test(
    'resolves ambiguous null-aware indexes at shorthand context boundaries',
    () {
      for (final text in ['.a?[i] : x', '.a()?[i] : x', 'a..b = .a?[i] : x']) {
        final expression = parsed(text);
        final conditional = expression is CascadeExpression
            ? (expression.sections.single as AssignmentExpression).right
                  as ConditionalExpression
            : expression as ConditionalExpression;
        expect(conditional.condition, isA<DotShorthandExpression>());
        expect(conditional.thenExpression, isA<CollectionExpression>());
      }
      final node = parsed('[?.x]') as CollectionExpression;
      expect(
        (node.elements.single as NullAwareElement).expression,
        isA<DotShorthandExpression>(),
      );
      expect(parse('.a?[i]?[j]:x').hasErrors, isTrue);
      expect(
        (parsed('.a()?[i]') as DotShorthandExpression).expression,
        isA<IndexExpression>(),
      );
    },
  );

  test('keeps prefix and postfix boundaries after terminal assertions', () {
    final conditional =
        parsed('!const .new()!! ? a : b') as ConditionalExpression;
    final assertion = conditional.condition as NullAssertionExpression;
    final prefix = assertion.operand as UnaryExpression;
    expect(prefix.op, UnaryOperator.logicalNot);
    expect(prefix.operand, isA<NullAssertionExpression>());
    expect(
      (prefix.operand as NullAssertionExpression).operand,
      isA<DotShorthandExpression>(),
    );
    for (final text in ['a!!.x', 'a.f()!![i]', 'a!! ? b : c']) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    expect(parsed('(a!!).x'), isA<PropertyAccessExpression>());
  });

  test(
    'applies type arguments to the written prefix and assertion boundary',
    () {
      for (final text in [
        'a!!<T>',
        'a!!<T>()',
        '.a!!<T>()',
        'const .new()!<T>()',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      final call = parsed('-a!!<T>()') as InvocationExpression;
      final prefix = call.callee as UnaryExpression;
      expect(prefix.op, UnaryOperator.negate);
      expect(prefix.operand.text, 'a!!');
      expect(walk(call).whereType<NullAssertionExpression>(), hasLength(2));
      expect(call.typeArguments!.text, '<T>');
      expect(
        (parsed('-const .new()!<T>()') as InvocationExpression).callee,
        isA<UnaryExpression>(),
      );
      final cascade = parsed('a..x!!<T>()') as CascadeExpression;
      expect(cascade.sections.single, isA<InvocationExpression>());
      expect(
        (parsed('.a!<T>()') as DotShorthandExpression).expression,
        isA<InvocationExpression>(),
      );
    },
  );

  test(
    'preserves later arguments after incomplete cascade and shorthand heads',
    () {
      final call =
          parse('f(a.., const .new, . , x)').node as InvocationExpression;
      expect(call.arguments.arguments.map((a) => a.value.text), [
        'a..',
        'const .new',
        '. ',
        'x',
      ]);
      for (final text in [
        'a..',
        'a..[]',
        'a..[',
        'a..x =',
        '.f(',
        'const .new(',
        'a..x..',
      ]) {
        final result = parse(text);
        expect(result.hasErrors, isTrue, reason: text);
        for (final node in walk(result.node)) {
          expect(node.end, inInclusiveRange(node.start, text.length));
        }
      }
    },
  );

  test(
    'handles deep shorthand arguments and cascade nesting without recursion',
    () {
      const depth = 12000;
      for (final (open, leaf, close) in [
        ('.f(', 'x', ')'),
        ('a..x = (', 'x', ')'),
      ]) {
        final text = '${open * depth}$leaf${close * depth}';
        final node = parsed(text);
        expect(node.text, text);
        expect(walk(node).length, greaterThan(depth));
      }
      final node = parsed('a${'..x = b' * depth}') as CascadeExpression;
      expect(node.sections, hasLength(depth));
      expect(node.target.text, 'a');
    },
  );

  test(
    'recovers malformed access chains without changing tokens or source ranges',
    () {
      final random = Random(7513);
      const fragments = [
        'a',
        '1',
        'new',
        'const',
        '.',
        '..',
        '?..',
        '?.',
        '!',
        '++',
        '?',
        ':',
        '=',
        '+',
        '(',
        ')',
        '[',
        ']',
        '<T>',
        ',',
        '[]',
        '[]=',
      ];
      for (var i = 0; i < 1600; i++) {
        final text = [
          for (var n = random.nextInt(25); n > 0; n--)
            fragments[random.nextInt(fragments.length)],
        ].join(' ');
        final input = scan(SourceFile(Uri.parse('memory:access'), text));
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
