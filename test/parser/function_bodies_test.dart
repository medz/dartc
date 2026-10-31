import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<FunctionBody> parse(String text) =>
    parseFunctionBody(scan(SourceFile(Uri.parse('memory:body'), text)));

FunctionBody parsed(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text.length < 200 ? text : '${text.length} characters',
  );
  return result.node;
}

void main() {
  test('parses declaration bodies with their written delimiters', () {
    expect(parsed(';'), isA<EmptyFunctionBody>());
    expect(parsed('{}'), isA<BlockStatement>());
    final arrow = parsed('=> x + 1;') as ExpressionFunctionBody;
    expect(arrow.isAsync, isFalse);
    expect(arrow.text, '=> x + 1;');
    expect(arrow.expression.text, 'x + 1');
    expect(parsed(' /* comment */ {} ').text, '{}');
    expect(parse('=> x').hasErrors, isTrue);
    expect(parse('{};').hasErrors, isTrue);
  });

  test('retains asynchronous and generator body modifiers', () {
    for (final (text, modifier) in [
      ('async {}', FunctionBodyModifier.asyncKeyword),
      ('sync* {}', FunctionBodyModifier.syncStar),
      ('async* {}', FunctionBodyModifier.asyncStar),
    ]) {
      final body = parsed(text) as ModifiedBlockFunctionBody;
      expect(body.modifier, modifier);
      expect(body.text, text);
      expect(body.block.text, '{}');
    }
    final arrow = parsed('async => await f();') as ExpressionFunctionBody;
    expect(arrow.isAsync, isTrue);
    expect(arrow.expression, isA<AwaitExpression>());
    expect(arrow.expression.text, 'await f()');
  });

  test(
    'await binds to its unary operand before binary and cascade operators',
    () {
      Expression expression(String text) =>
          (parsed('async => $text;') as ExpressionFunctionBody).expression;
      final sum = expression('await f() + x') as BinaryExpression;
      expect(sum.left, isA<AwaitExpression>());
      final awaited = expression('await -x') as AwaitExpression;
      expect(awaited.expression, isA<UnaryExpression>());
      final negated = expression('-await x') as UnaryExpression;
      expect(negated.operand, isA<AwaitExpression>());
      final cascade = expression('await f()..field = x') as CascadeExpression;
      expect(cascade.target, isA<AwaitExpression>());
      expect(
        (expression('await x as T') as CastExpression).expression,
        isA<AwaitExpression>(),
      );
      expect(
        (expression('await x is T') as TypeTestExpression).expression,
        isA<AwaitExpression>(),
      );
      expect(
        (expression('await x!') as AwaitExpression).expression,
        isA<NullAssertionExpression>(),
      );
      expect(
        (expression('await await x') as AwaitExpression).expression,
        isA<AwaitExpression>(),
      );
    },
  );

  test('passes async context through conditional trials and interpolation', () {
    final arrow =
        parsed('async => flag?[await x]:await y;') as ExpressionFunctionBody;
    final condition = arrow.expression as ConditionalExpression;
    expect(condition.elseExpression, isA<AwaitExpression>());
    expect(walk(condition).whereType<AwaitExpression>(), hasLength(2));
    final string =
        parsed(r'async => "${await value}";') as ExpressionFunctionBody;
    expect(walk(string).whereType<AwaitExpression>(), hasLength(1));
    expect(parse(r'async => "$await";').hasErrors, isTrue);
  });

  test('parses yield, yield star and empty returns in generators', () {
    for (final modifier in ['sync*', 'async*']) {
      final body = parsed(
        '$modifier { yield x; yield* xs; return; }',
      ) as ModifiedBlockFunctionBody;
      final statements = body.block.statements;
      expect((statements[0] as YieldStatement).isStar, isFalse);
      expect((statements[1] as YieldStatement).isStar, isTrue);
      expect((statements.last as ReturnStatement).expression, isNull);
      expect(parse('$modifier { return 1; }').hasErrors, isTrue);
      expect(parse('$modifier => 1;').hasErrors, isTrue);
    }
    expect(parse('async { yield 1; }').hasErrors, isTrue);
    expect(parse('async { yield* xs; }').hasErrors, isTrue);
    expect(parse('sync* { yield; }').hasErrors, isTrue);
    expect(parse('sync* { await f(); }').hasErrors, isTrue);
  });

  test('parses asynchronous for-in statements and collection elements', () {
    final body = parsed(
      'async { await for (final x in stream) { print(x); } }',
    ) as ModifiedBlockFunctionBody;
    final loop = body.block.statements.single as ForStatement;
    expect(loop.isAwait, isTrue);
    expect(loop.parts, isA<ForInParts>());
    final arrow = parsed(
      'async => [await for (var x in stream) await f(x)];',
    ) as ExpressionFunctionBody;
    final element =
        (arrow.expression as CollectionExpression).elements.single
            as ForElement;
    expect(element.isAwait, isTrue);
    expect(element.parts, isA<ForInParts>());
    for (final text in [
      'async { await for (;;) {} }',
      'async => [await for (;;) x];',
      '{ await for (var x in stream) {} }',
      'sync* { await for (var x in stream) {} }',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test('reserves async words in values and keeps type names unresolved', () {
    for (final word in ['await', 'yield']) {
      expect(parsed('{ var $word = 1; print($word); }'), isA<BlockStatement>());
      for (final modifier in ['async', 'sync*', 'async*']) {
        for (final statement in [
          'var $word = 1;',
          'x.$word;',
          'f($word: 1);',
        ]) {
          expect(parse('$modifier { $statement }').hasErrors, isTrue);
        }
        for (final type in [
          'T Function(int $word)',
          '(int $word,)',
          '({int $word})',
        ]) {
          expect(parse('$modifier { <$type>[]; }').hasErrors, isTrue);
        }
        expect(
          parsed('$modifier { <T Function<$word>()>[]; }'),
          isA<ModifiedBlockFunctionBody>(),
        );
      }
    }
    expect(
      parsed('async { List<await> values; p.yield value; }'),
      isA<ModifiedBlockFunctionBody>(),
    );
    expect(parse('{ await: while (true) break await; }').hasErrors, isTrue);
    expect(
      parsed('{ label: await: while (true) break await; }'),
      isA<BlockStatement>(),
    );
  });

  test('returns a distinct missing body and rejects invalid modifiers', () {
    final missing = parse('');
    expect(missing.hasErrors, isTrue);
    expect(missing.node, isA<MissingFunctionBody>());
    expect(missing.node.start, 0);
    expect(missing.node.end, 0);
    expect(missing.node.childCount, 0);
    expect(parse('async').node.start, 5);
    for (final text in ['async', 'sync {}', 'async;', 'sync*;', 'async*;']) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test('handles deep awaits and blocks without recursive calls', () {
    const depth = 12000;
    final arrow = parsed('async => ${'await ' * depth}x;');
    expect(walk(arrow).whereType<AwaitExpression>(), hasLength(depth));
    final block = parsed('async ${'{' * depth} await f(); ${'}' * depth}');
    expect(walk(block).whereType<BlockStatement>(), hasLength(depth));
  });

  test(
    'recovers malformed bodies without mutating tokens or source ranges',
    () {
      final random = Random(7319);
      const fragments = [
        'async',
        'sync',
        '*',
        'await',
        'yield',
        'return',
        'for',
        'in',
        'var',
        'const',
        'final',
        'try',
        'catch',
        'if',
        'else',
        'void',
        'Function',
        'a',
        '1',
        '.',
        '..',
        '?',
        ':',
        ',',
        ';',
        '=>',
        '=',
        '<',
        '>',
        '(',
        ')',
        '[',
        ']',
        '{',
        '}',
        '!',
        '+',
      ];
      for (var i = 0; i < 3000; i++) {
        final content = [
          for (var n = random.nextInt(40); n > 0; n--)
            fragments[random.nextInt(fragments.length)],
        ].join(' ');
        final text = '${['', 'async ', 'sync* ', 'async* '][i % 4]}{$content}';
        final input = scan(
          SourceFile(Uri.parse('memory:malformed-body'), text),
        );
        final tokens = [...input.tokens];
        final result = parseFunctionBody(input);
        expect(input.tokens, orderedEquals(tokens));
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
