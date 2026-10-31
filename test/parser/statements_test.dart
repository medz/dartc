import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart' as expressions;

ParseResult<Statement> parse(String text) =>
    parseStatement(scan(SourceFile(Uri.parse('memory:statement'), text)));

Statement parsed(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text.length < 300 ? text : 'source length ${text.length}',
  );
  return result.node;
}

void main() {
  test('retains block braces, empty statements and source order', () {
    final block = parsed('{; a(); { b(); } ;}') as BlockStatement;
    expect(block.statements.map((s) => s.text), [';', 'a();', '{ b(); }', ';']);
    expect(block.statements.first, isA<EmptyStatement>());
    expect(() => block.statements.clear(), throwsUnsupportedError);
    expect(parsed('{}'), isA<BlockStatement>());
    expect(parsed('a..x = .new();'), isA<ExpressionStatement>());
    expect(parse('a(); b();').hasErrors, isTrue);
  });

  test('associates else with the nearest unfinished if', () {
    final outer = parsed('if (a) if (b) x(); else y();') as IfStatement;
    final inner = outer.thenStatement as IfStatement;
    expect(outer.elseStatement, isNull);
    expect(inner.elseStatement!.text, 'y();');
    final grouped = parsed('if (a) {if (b) x();} else y();') as IfStatement;
    expect(grouped.thenStatement, isA<BlockStatement>());
    expect(grouped.elseStatement!.text, 'y();');
    expect(
      (parsed('if (a?[i] : b) ;') as IfStatement).condition,
      isA<ConditionalExpression>(),
    );
  });

  test('keeps written loop conditions and do-while order', () {
    final infinite = parsed('while (true) {}') as WhileStatement;
    expect(infinite.condition.text, 'true');
    expect(infinite.body, isA<BlockStatement>());
    final loop = parsed('do { work(); } while (check());') as DoStatement;
    expect(loop.body.text, '{ work(); }');
    expect(loop.condition.text, 'check()');
    expect(loop.childAt(0), same(loop.body));
    expect(loop.childAt(1), same(loop.condition));
    expect(loop.text.endsWith(';'), isTrue);
  });

  test('uses the shared for header syntax without inserting a condition', () {
    final empty = parsed('for (;;) ;') as ForStatement;
    final parts = empty.parts as ForParts;
    expect(parts.initializer, isNull);
    expect(parts.condition, isNull);
    expect(parts.updaters, isEmpty);
    expect(parts.text, ';;');
    final loop = parsed(
      'for (var i = 0, j = 1; i < n; i++, j += 2) work(i, j);',
    ) as ForStatement;
    final header = loop.parts as ForParts;
    final variables = header.initializer as VariableDeclarationList;
    expect(variables.declarations.map((v) => v.name.text), ['i', 'j']);
    expect(header.updaters.map((u) => u.text), ['i++', 'j += 2']);
    expect(loop.body.text, 'work(i, j);');
    final existing =
        (parsed('for (x in xs) ;') as ForStatement).parts as ForInParts;
    expect(existing.target, isA<Identifier>());
    final declared =
        (parsed('for (final T x in xs) ;') as ForStatement).parts as ForInParts;
    expect((declared.target as DeclaredIdentifier).type!.text, 'T');
    expect(declared.iterable.text, 'xs');
    expect(parse('await for (var x in xs) ;').hasErrors, isTrue);
  });

  test('parses local variables and retains omitted initializers', () {
    final statement = parsed(
      'late final List<T>? values = .new(), next;',
    ) as VariableDeclarationStatement;
    final list = statement.variables;
    expect(list.isLate, isTrue);
    expect(list.keyword, VariableKeyword.finalKeyword);
    expect(list.type!.text, 'List<T>?');
    expect(list.declarations.first.initializer, isA<DotShorthandExpression>());
    expect(list.declarations.last.initializer, isNull);
    expect(list.text, 'late final List<T>? values = .new(), next');
    for (final text in [
      'var x = a..b;',
      'int get = 1;',
      '(int, String) record;',
      'final dynamic Function<T>(T) f = callback;',
      'late var value;',
      'late (T, U)? pair;',
      'const (T, U)? pair = value;',
      'const Function()? callback = value;',
    ]) {
      expect(parsed(text), isA<VariableDeclarationStatement>(), reason: text);
    }
  });

  test('distinguishes nullable declarations from conditional expressions', () {
    for (final text in ['T? x = a;', '(T, U)? x = a;', 'Function()? x = a;']) {
      expect(parsed(text), isA<VariableDeclarationStatement>(), reason: text);
    }
    for (final text in ['T? x = a : b;', '(a, b)? x = y : z;']) {
      final statement = parsed(text) as ExpressionStatement;
      expect(statement.expression, isA<ConditionalExpression>(), reason: text);
    }
    final conditional =
        (parsed('for (T? x = a : b;;) ;') as ForStatement).parts as ForParts;
    expect(conditional.initializer, isA<ConditionalExpression>());
    final declaration =
        (parsed('for (T? x = a;;) ;') as ForStatement).parts as ForParts;
    expect(declaration.initializer, isA<VariableDeclarationList>());
  });

  test(
    'distinguishes typed declarations from call and assignment prefixes',
    () {
      for (final type in [
        'T',
        'prefix.Type',
        'prefix.Type<Argument>?',
        'T Function<U>(U)',
        'Function<T>(T)',
        'void Function()',
        '(T, {int count})',
        '(T,) Function(U)',
      ]) {
        for (final modifier in ['', 'final ']) {
          final statement = parsed(
            '$modifier$type value = input;',
          ) as VariableDeclarationStatement;
          expect(statement.variables.type!.text, type);
          expect(statement.variables.declarations.single.name.text, 'value');
          expect(
            statement.variables.declarations.single.initializer!.text,
            'input',
          );
        }
      }
      for (final text in [
        'value = other;',
        'value += other;',
        'value.member(argument);',
        'prefix.Constructor<Argument>();',
        'value?.member(argument);',
        'value?[index] = other;',
        'value.member<Type>(argument);',
        'value ? left : right;',
      ]) {
        final statement = parsed(text) as ExpressionStatement;
        expect(statement.expression.text, text.substring(0, text.length - 1));
      }
    },
  );

  test('keeps const expressions distinct from variable declarations', () {
    for (final text in [
      'late(a);',
      'const C();',
      'const p.C();',
      'const <T>[];',
      'const (1,);',
      'const .new();',
      'const .value;',
    ]) {
      expect(parsed(text), isA<ExpressionStatement>(), reason: text);
    }
    for (final text in [
      'const x = 1;',
      'const T x = value;',
      'const p.T x = value;',
    ]) {
      expect(parsed(text), isA<VariableDeclarationStatement>(), reason: text);
    }
    expect(
      (parsed('for ((const C());;) ;') as ForStatement).parts,
      isA<ForParts>(),
    );
  });

  test('retains labels and jumps without resolving targets', () {
    final labeled = parsed(
      'outer: inner: while (ready) {continue inner; break outer;}',
    ) as LabeledStatement;
    expect(labeled.labels.map((l) => l.text), ['outer:', 'inner:']);
    final body = (labeled.statement as WhileStatement).body as BlockStatement;
    expect((body.statements.first as ContinueStatement).label!.text, 'inner');
    expect((body.statements.last as BreakStatement).label!.text, 'outer');
    expect((parsed('return;') as ReturnStatement).expression, isNull);
    expect(
      (parsed('return value;') as ReturnStatement).expression!.text,
      'value',
    );
    expect(parsed('rethrow;'), isA<RethrowStatement>());
  });

  test('retains assert conditions, messages and optional trailing commas', () {
    for (final text in ['assert(ok);', 'assert(ok,);']) {
      expect((parsed(text) as AssertStatement).message, isNull);
    }
    final node = parsed('assert(test(), makeMessage(),);') as AssertStatement;
    expect(node.condition.text, 'test()');
    expect(node.message!.text, 'makeMessage()');
    expect(parse('assert();').hasErrors, isTrue);
    expect(parse('assert(a, b, c);').hasErrors, isTrue);
  });

  test('retains try, ordered catches and finally without implicit types', () {
    final node = parsed(
      'try {work();} on p.Error<T> catch(e, stack) {report(e);} catch(e) {rethrow;} finally {close();}',
    ) as TryStatement;
    expect(node.body.statements.single.text, 'work();');
    expect(node.catchClauses, hasLength(2));
    final typed = node.catchClauses.first;
    expect(typed.exceptionType!.text, 'p.Error<T>');
    expect(typed.exceptionParameter!.text, 'e');
    expect(typed.stackTraceParameter!.text, 'stack');
    expect(node.catchClauses.last.exceptionType, isNull);
    expect(node.catchClauses.last.stackTraceParameter, isNull);
    expect(node.finallyBlock!.text, '{close();}');
    expect((parsed('try {} finally {}') as TryStatement).catchClauses, isEmpty);
    expect(
      (parsed(
        'try {} on T {}',
      ) as TryStatement).catchClauses.single.exceptionParameter,
      isNull,
    );
  });

  test('parses throw expressions at expression boundaries', () {
    for (final MapEntry(:key, :value) in {
      'throw a..b': '(throw (cascade a (.. b)))',
      'a..b = throw c..d': '(cascade a (= (.. b) (throw c)) (.. d))',
      'a ? throw b : throw c': '(?: a (throw b) (throw c))',
      'throw throw a': '(throw (throw a))',
      'a ?? (throw b)': '(?? a (group (throw b)))',
      'throw a = b': '(throw (= a b))',
    }.entries) {
      expect(expressions.shape(expressions.parsed(key)), value, reason: key);
    }
    for (final text in ['a ?? throw b', 'a + throw b', '-throw b']) {
      expect(expressions.parse(text).hasErrors, isTrue, reason: text);
    }
    expect(
      (parsed('throw problem;') as ExpressionStatement).expression,
      isA<ThrowExpression>(),
    );
    expect(
      (parsed('return throw problem;') as ReturnStatement).expression,
      isA<ThrowExpression>(),
    );
  });

  test('recovers incomplete statements and retains subsequent statements', () {
    for (final text in [
      '',
      'if () ;',
      'while (a)',
      'do ;',
      'for (var x in) ;',
      'try {}',
      'try {} catch() {}',
      'try {} finally ;',
      'return a',
      'outer:',
      'if(a) else ;',
      'var ;',
      'late x;',
      'late const x = 1;',
      'static (T, U)? x = a : b;',
      'external (T, U)? x;',
      'late late var x;',
      'Function()? x = y : z;',
      'for (const C();;) ;',
      'late (T, U)? x = a : b;',
      'const (T, U)? x = a : b;',
      'var x =;',
      'const .;',
      'assert(a, b, c);',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    final block =
        parse('{ return 1 var x = 2; if (ok) ; }').node as BlockStatement;
    expect(block.statements, hasLength(3));
    expect(block.statements[1], isA<VariableDeclarationStatement>());
    expect(block.statements.last, isA<IfStatement>());
  });

  test('handles deep blocks and control flow without recursive parsing', () {
    const count = 12000;
    for (final (open, close) in [
      ('{', '}'),
      ('if (ok) ', ''),
      ('while (ok) ', ''),
      ('for (;;) ', ''),
    ]) {
      final text = '${open * count};${close * count}';
      final node = parsed(text);
      expect(node.text, text);
      expect(walk(node).length, greaterThan(count));
    }
    final labels = parsed('${'label: ' * count};') as LabeledStatement;
    expect(labels.labels, hasLength(count));
    final thrown = expressions.parsed('${'throw ' * count}x');
    expect(walk(thrown).whereType<ThrowExpression>(), hasLength(count));
  });

  test(
    'recovers malformed statements without mutating tokens or escaping ranges',
    () {
      final random = Random(9191);
      const fragments = [
        'if',
        'else',
        'while',
        'do',
        'for',
        'try',
        'on',
        'catch',
        'finally',
        'return',
        'throw',
        'rethrow',
        'assert',
        'break',
        'continue',
        'var',
        'final',
        'const',
        'late',
        'x',
        'T',
        '1',
        '(',
        ')',
        '{',
        '}',
        '[',
        ']',
        '=',
        ':',
        ';',
        ',',
        '?',
        '?..',
        '.',
        '+',
      ];
      for (var i = 0; i < 2000; i++) {
        final text = [
          for (var n = random.nextInt(35); n > 0; n--)
            fragments[random.nextInt(fragments.length)],
        ].join(' ');
        final input = scan(
          SourceFile(Uri.parse('memory:statement-fuzz'), text),
        );
        final tokens = [...input.tokens];
        final result = parseStatement(input);
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
