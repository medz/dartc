import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('retains unresolved constructor names and written argument order', () {
    final node =
        parsed('new p.C.named(x, flag: y, z,)') as InstanceCreationExpression;
    expect(node.kind, InstanceCreationKind.newKeyword);
    expect(node.name.map((n) => n.text), ['p', 'C', 'named']);
    expect(node.constructorName, isNull);
    expect(node.typeArguments, isNull);
    expect(node.arguments.text, '(x, flag: y, z,)');
    expect(node.arguments.arguments.map((a) => a.name?.text), [
      null,
      'flag',
      null,
    ]);
    expect(node.arguments.arguments.map((a) => a.value.text), ['x', 'y', 'z']);
    expect(() => node.name.clear(), throwsUnsupportedError);
    final ambiguous = parsed('const C.named(1)') as InstanceCreationExpression;
    expect(ambiguous.kind, InstanceCreationKind.constKeyword);
    expect(ambiguous.name.map((n) => n.text), ['C', 'named']);
    expect(ambiguous.constructorName, isNull);
  });

  test(
    'keeps type arguments before the constructor name and handles new names',
    () {
      final node = parsed(
        'new p.C<Map<String, List<T>>>.named(x)',
      ) as InstanceCreationExpression;
      expect(node.name.map((n) => n.text), ['p', 'C']);
      expect(node.typeArguments!.text, '<Map<String, List<T>>>');
      expect(node.constructorName!.text, 'named');
      for (final text in [
        'new C.new()',
        'new p.C.new()',
        'new C<T>.new()',
        'const p.C<T>.new()',
      ]) {
        final value = parsed(text) as InstanceCreationExpression;
        expect(value.constructorName?.text ?? value.name.last.text, 'new');
      }
      final prefixed = parsed('new p.C<T>()') as InstanceCreationExpression;
      expect(prefixed.name.map((n) => n.text), ['p', 'C']);
      for (final name in ['get', 'dynamic', 'Function', 'await', 'type']) {
        expect(
          (parsed(
            'new $name()',
          ) as InstanceCreationExpression).name.single.text,
          name,
        );
      }
    },
  );

  test('parses selectors and nested constructors using the argument stack', () {
    final node = parsed(
      'new C(new D(), named: const E()).values[0].run<int>(x)',
    ) as InvocationExpression;
    final property = node.callee as PropertyAccessExpression;
    expect(property.property.text, 'run');
    final index = property.target as IndexExpression;
    final access = index.target as PropertyAccessExpression;
    final construction = access.target as InstanceCreationExpression;
    expect(
      construction.arguments.arguments.map(
        (a) => (a.value as InstanceCreationExpression).kind,
      ),
      [InstanceCreationKind.newKeyword, InstanceCreationKind.constKeyword],
    );
    expect(node.typeArguments!.text, '<int>');
    final genericCall = parsed('C<T>(x)') as InvocationExpression;
    expect(genericCall.callee.text, 'C');
  });

  test('rejects malformed constructor references without inventing names', () {
    for (final text in [
      'new',
      'const',
      'new void()',
      'new 1()',
      'new C',
      'new C<>.named()',
      'new C<T,>()',
      'new p.C.named<T>()',
      'new a.b.c.d()',
      'new C?.named()',
      'new C<T>?.named()',
      'new C<T>.',
      'new C.()',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    final incomplete = parse('f(new C, x)');
    expect(incomplete.hasErrors, isTrue);
    final call = incomplete.node as InvocationExpression;
    expect(call.arguments.arguments.last.text, 'x');
    final constructor =
        call.arguments.arguments.first.value as InstanceCreationExpression;
    expect(constructor.arguments.start, constructor.arguments.end);
    expect(constructor.arguments.arguments, isEmpty);
    final missing = parse('new ()').node as InstanceCreationExpression;
    expect(missing.name.single.text, isEmpty);
  });

  test(
    'parses const records and requires a comma for one positional field',
    () {
      for (final text in [
        'const ()',
        'const (x,)',
        'const (x, y)',
        'const (name: x)',
        'const (x, name: y, z,)',
      ]) {
        final node = parsed(text) as RecordExpression;
        expect(node.hasConstKeyword, isTrue);
        expect(node.text, text);
      }
      final node = parsed('const (x, name: const (y,), z)') as RecordExpression;
      expect(node.fields.map((n) => n.text), ['x', 'name: const (y,)', 'z']);
      expect(
        (parsed('const (x,).\$1') as PropertyAccessExpression).target,
        isA<RecordExpression>(),
      );
      final malformed = parse('const (x)');
      expect(malformed.diagnostics.map((d) => d.code), [
        'parser.expected_record_comma',
      ]);
      expect(malformed.node, isA<RecordExpression>());
      expect((malformed.node as RecordExpression).hasConstKeyword, isTrue);
      expect(parsed('(x)'), isA<ParenthesizedExpression>());
    },
  );

  test('parses symbol names and operators without resolving their values', () {
    for (final text in [
      '#name',
      '#a.b.c',
      '#_private',
      '#void',
      '#get',
      '#await',
      '#type',
      '#a.get',
      '#+',
      '#-',
      '#*',
      '#/',
      '#~/',
      '#%',
      '#&',
      '#|',
      '#^',
      '#~',
      '#<',
      '#<=',
      '#>',
      '#>=',
      '#<<',
      '#>>',
      '#>>>',
      '#==',
      '#[]',
      '#[]=',
      '# /*😀*/ a . b',
    ]) {
      final node = parsed(text) as LiteralExpression;
      expect(node.kind, LiteralKind.symbol);
      expect(node.text, text);
    }
    final access = parsed('#void.foo') as PropertyAccessExpression;
    expect(access.target.text, '#void');
    expect(access.property.text, 'foo');
    for (final text in [
      '#',
      '#true',
      '#if',
      '#new',
      '#foo.new',
      '#foo.void',
      '#foo.',
      '#[ ]',
      '#!=',
      '#&&',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    final call = parse('f(#, x)').node as InvocationExpression;
    expect(call.arguments.arguments.last.text, 'x');
  });

  test('parses super receivers and supported operator positions', () {
    for (final (text, expected) in [
      ('super.value', '(. super value)'),
      ('super.run(x)', '(call (. super run) x)'),
      ('super(x)', '(call super x)'),
      ('super?[x]', '(?[] super x)'),
      ('super[x]', '([] super x)'),
      ('super[x] = y', '(= ([] super x) y)'),
      ('super.value++', '(post++ (. super value))'),
      ('-super', '(- super)'),
      ('~super', '(~ super)'),
      ('super + x * y', '(+ super (* x y))'),
      ('super == x', '(== super x)'),
      ('super != x', '(!= super x)'),
      ('x + super * y', '(+ x (* super y))'),
    ]) {
      expect(shape(parsed(text)), expected);
    }
    for (final text in [
      'super',
      'super!',
      'super<T>',
      '(super)',
      'x + super',
      'super ?? x',
      'super && x',
      'super || x',
      'super as T',
      'super is T',
      'super ? x : y',
      'x ? super : y',
      '!super',
      'super = x',
      '++super',
      'super++',
      'super?.x',
      'f(super)',
      '[super]',
      '{super}',
      r'"${super}"',
      'super?[x] : y',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test(
    'combines primaries with interpolation, collections and ambiguity trials',
    () {
      final node = parsed(
        r'"${const (new C(), #a, super.value)}"',
      ) as InterpolatedStringExpression;
      final record =
          (node.parts[1] as StringInterpolation).expression as RecordExpression;
      expect(record.fields, hasLength(3));
      final conditional =
          parsed('a ? [const (1,), new C(), #a] : b') as ConditionalExpression;
      expect(
        (conditional.thenExpression as CollectionExpression).elements,
        hasLength(3),
      );
      final index = parsed('new C()?[#key]') as IndexExpression;
      expect(index.target, isA<InstanceCreationExpression>());
      expect(parsed('new C()[x]?[y]?[z]:w'), isA<ConditionalExpression>());
      expect(parse('super()?[x]?[y]:z').hasErrors, isTrue);
      expect(parse('this()?[x]?[y]:z').hasErrors, isTrue);
    },
  );

  test('keeps immutable tokens and source ownership during type splitting', () {
    final input = scan(
      SourceFile(
        Uri.parse('memory:constructor'),
        'new p.C<List<T>>.named(const (1,), #key)',
      ),
    );
    final before = input.tokens
        .map((t) => (t.kind, t.start, t.end, t.lexeme))
        .toList();
    final result = parseExpression(input);
    expect(result.hasErrors, isFalse);
    expect(
      walk(result.node).every((n) => identical(n.source, input.source)),
      isTrue,
    );
    expect(input.tokens.map((t) => (t.kind, t.start, t.end, t.lexeme)), before);
  });

  test('handles deep construction and record nesting without recursion', () {
    const depth = 12000;
    final constructors = parsed('${'new C(' * depth}x${')' * depth}');
    expect(
      walk(constructors).whereType<InstanceCreationExpression>(),
      hasLength(depth),
    );
    final records = parsed('${'const (' * depth}x${',)' * depth}');
    expect(walk(records).whereType<RecordExpression>(), hasLength(depth));
    final symbol = parsed('#a${'.a' * depth}') as LiteralExpression;
    expect(symbol.end, 2 + depth * 2);
  });

  test('recovers malformed primaries within their source ranges', () {
    final random = Random(87021);
    const fragments = [
      'new',
      'const',
      'super',
      '#',
      'p',
      'C',
      'x',
      'void',
      '.',
      '?.',
      '?',
      ':',
      '(',
      ')',
      '[',
      ']',
      '<',
      '>',
      '>>=',
      '1',
      ',',
      '+',
      '=',
      ';',
    ];
    for (var i = 0; i < 1500; i++) {
      final text = List.generate(
        random.nextInt(30),
        (_) => fragments[random.nextInt(fragments.length)],
      ).join(' ');
      final input = scan(SourceFile(Uri.parse('memory:malformed'), text));
      final result = parseExpression(input);
      for (final node in walk(result.node)) {
        expect(node.source, same(input.source));
        expect(node.start, inInclusiveRange(0, text.length));
        expect(node.end, inInclusiveRange(node.start, text.length));
      }
    }
  });
}
