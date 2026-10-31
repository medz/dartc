import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<Expression> parse(String text) =>
    parseExpression(scan(SourceFile(Uri.parse('memory:function'), text)));

Expression expression(String text) {
  final result = parse(text);
  expect(result.diagnostics, isEmpty, reason: text.length < 200 ? text : null);
  return result.node;
}

Statement statement(String text) {
  final result = parseStatement(
    scan(SourceFile(Uri.parse('memory:local'), text)),
  );
  expect(result.diagnostics, isEmpty, reason: text.length < 200 ? text : null);
  return result.node;
}

void main() {
  test('retains closure parameters, generic bounds and body ranges', () {
    final function =
        expression('<T extends Object>(T x) => x') as FunctionExpression;
    expect(function.typeParameters!.parameters.single.bound!.text, 'Object');
    expect(function.parameters.text, '(T x)');
    expect(function.body.text, '=> x');
    expect(function.text, '<T extends Object>(T x) => x');
    final block = expression('() { return 1; }') as FunctionExpression;
    expect(block.body, isA<BlockStatement>());
    expect(parse('() => 1;').hasErrors, isTrue);
  });

  test(
    'distinguishes functions, groups, records, calls and typed collections',
    () {
      expect(expression('()'), isA<RecordExpression>());
      expect(expression('(x)'), isA<ParenthesizedExpression>());
      expect(expression('(x,)'), isA<RecordExpression>());
      expect(expression('(x) => x'), isA<FunctionExpression>());
      expect(expression('<T>[]'), isA<CollectionExpression>());
      expect(expression('<T>(T x) => x'), isA<FunctionExpression>());
      expect(expression('(() => 1)()'), isA<InvocationExpression>());
      final call = expression(
        'f((x) => x + 1, () { return 2; })',
      ) as InvocationExpression;
      expect(
        call.arguments.arguments.map((a) => a.value),
        everyElement(isA<FunctionExpression>()),
      );
    },
  );

  test(
    'arrow bodies own their operators, cascades and conditional expressions',
    () {
      final function = expression('() => x ? y : z..f()') as FunctionExpression;
      final body = function.body as ExpressionFunctionBody;
      expect(body.expression, isA<CascadeExpression>());
      final condition =
          expression('flag ? () => x : () => y') as ConditionalExpression;
      expect(condition.thenExpression, isA<FunctionExpression>());
      expect(condition.elseExpression, isA<FunctionExpression>());
      final indexed =
          expression('flag?[() => x]:() => y') as ConditionalExpression;
      expect(indexed.thenExpression, isA<CollectionExpression>());
      expect(indexed.elseExpression, isA<FunctionExpression>());
    },
  );

  test('parses closures in defaults, annotations and collection controls', () {
    final function = expression(
      '(@A(() => 1) int x, {f = () => 2}) => f()',
    ) as FunctionExpression;
    expect(walk(function).whereType<FunctionExpression>(), hasLength(3));
    expect(
      function.parameters.parameters.first.metadata.single.arguments!.text,
      '(() => 1)',
    );
    final defaults = parseFormalParameterList(
      scan(SourceFile(Uri.parse('memory:parameters'), '({f = () => 1})')),
    );
    expect(defaults.diagnostics, isEmpty);
    expect(walk(defaults.node).whereType<FunctionExpression>(), hasLength(1));
    expect(
      expression('[for(var f = () => 1; f() > 0; f = () => 0) f()]'),
      isA<CollectionExpression>(),
    );
  });

  test(
    'local declarations retain metadata, types and terminating semicolons',
    () {
      final local = statement(
        '@A() T f<T extends Object>(T x) => x;',
      ) as LocalFunctionDeclaration;
      expect(local.metadata.single.text, '@A()');
      expect(local.returnType!.text, 'T');
      expect(local.name.text, 'f');
      expect(local.typeParameters!.text, '<T extends Object>');
      expect(local.body.text, '=> x;');
      final block = statement('{ f(x) { return x; } f(1); }') as BlockStatement;
      expect(block.statements.first, isA<LocalFunctionDeclaration>());
      expect(block.statements.last, isA<ExpressionStatement>());
    },
  );

  test('keeps function types and contextual function names distinct', () {
    for (final text in [
      'Function() f() {}',
      'void Function() {}',
      'int? Function() {}',
      '(int, String) Function() {}',
      'void Function<T>(T x) {}',
      'Function() Function() {}',
      'int Function() Function<T>(T x) {}',
      'late() {}',
      'async() {}',
      'Function() async() {}',
      'void late() async {}',
    ]) {
      expect(statement(text), isA<LocalFunctionDeclaration>(), reason: text);
    }
    expect(statement('Function() f;'), isA<VariableDeclarationStatement>());
    expect(statement('f();'), isA<ExpressionStatement>());
  });

  test('nested bodies enter and restore async and generator contexts', () {
    final function = expression(
      '() async { var f = () { var await = 1; return await; }; await f(); }',
    );
    expect(walk(function).whereType<AwaitExpression>(), hasLength(1));
    expect(
      expression('() sync* { f() { return 1; } yield f(); }'),
      isA<FunctionExpression>(),
    );
    expect(
      expression('() { var f = () async => await g(); var await = 1; }'),
      isA<FunctionExpression>(),
    );
    expect(
      expression(
        '() async* { var f = () sync* { yield 1; }; await g(); yield* f(); }',
      ),
      isA<FunctionExpression>(),
    );
    for (final text in [
      '() async { var f = () { await g(); }; }',
      '() sync* { f() { yield 1; } }',
      '() { var f = () async {}; await g(); }',
      '() sync* { f() { return 1; } return 2; }',
      '() async { void await() {} }',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test('parameter metadata and defaults use their enclosing context', () {
    for (final text in [
      '() async => ({f = await g()}) => f()',
      '() async => (@A(await g()) x) => x',
      '() async { f({x = await g()}) {} }',
      '(await) async {}',
    ]) {
      expect(expression(text), isA<FunctionExpression>());
    }
    for (final text in [
      '() async => ({f = await}) => f()',
      '() async => ({f = yield}) => f()',
      '() async => (int await) => 1',
      '({f = await g()}) async => f()',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test(
    'reports invalid function syntax without losing following statements',
    () {
      for (final text in [
        '(var x) => x',
        '(final x) => x',
        '(const x) => x',
        '() sync {}',
        '() sync* => 1',
        '() async* => 1',
        '() async { yield 1; }',
        '() sync* { return 1; }',
        '() =>',
        '(x,) =>',
        '() {',
        '<T>(T x) =>',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      final result = parseStatement(
        scan(
          SourceFile(
            Uri.parse('memory:recovery'),
            '{ int f() => ; return 1; }',
          ),
        ),
      );
      expect(result.hasErrors, isTrue);
      final statements = (result.node as BlockStatement).statements;
      expect(statements.first, isA<LocalFunctionDeclaration>());
      expect(statements.last, isA<ReturnStatement>());
    },
  );

  test(
    'handles deep function bodies, defaults, metadata and conditional trials',
    () {
      const depth = 12000;
      final arrow = expression('${'() => ' * depth}1');
      expect(walk(arrow).whereType<FunctionExpression>(), hasLength(depth));
      final blocks = expression('${'() { return ' * depth}1${'; }' * depth}');
      expect(walk(blocks).whereType<FunctionExpression>(), hasLength(depth));
      final locals = statement('${'f() { ' * depth}return;${'}' * depth}');
      expect(
        walk(locals).whereType<LocalFunctionDeclaration>(),
        hasLength(depth),
      );
      const otherDepth = 2000;
      for (final (opening, closing) in [
        ('({f = ', '}) => f'),
        ('(@A(', ') x) => x'),
        ('x?[() => ', ']:y'),
      ]) {
        final node = expression(
          '${opening * otherDepth}1${closing * otherDepth}',
        );
        expect(
          walk(node).whereType<FunctionExpression>(),
          hasLength(otherDepth),
        );
      }
    },
  );

  test('malformed nested functions terminate with bounded source ranges', () {
    final random = Random(8412);
    const pieces = [
      '(',
      ')',
      '{',
      '}',
      '=>',
      'async',
      'sync',
      '*',
      'await',
      'yield',
      'f',
      'int',
      '<',
      '>',
      ',',
      ';',
      ':',
      '?',
      '=',
      '@A',
      'return',
    ];
    for (var sample = 0; sample < 1000; sample++) {
      final text = List.generate(
        random.nextInt(40),
        (_) => pieces[random.nextInt(pieces.length)],
      ).join(' ');
      final input = scan(SourceFile(Uri.parse('memory:malformed'), text));
      for (final result in <ParseResult<AstNode>>[
        parseExpression(input),
        parseStatement(input),
      ]) {
        for (final node in walk(result.node)) {
          expect(node.source, same(input.source));
          expect(node.start, inInclusiveRange(0, text.length));
          expect(node.end, inInclusiveRange(node.start, text.length));
        }
      }
    }
  });
}
