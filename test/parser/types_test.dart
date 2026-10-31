import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

ParseResult<TypeAnnotation> parseType(String text) =>
    parseTypeAnnotation(scan(SourceFile(Uri.parse('memory:type'), text)));

TypeAnnotation type(String text) {
  final result = parseType(text);
  expect(
    result.diagnostics.map((d) => d.message),
    isEmpty,
    reason: text.length < 300 ? text : 'type length: ${text.length}',
  );
  return result.node;
}

void main() {
  test(
    'retains qualified names, nested type arguments and nullable ranges',
    () {
      const text = '/*😀*/ p.Map<String?, List<int>>?';
      final node = type(text) as NamedTypeAnnotation;
      expect(node.start, 7);
      expect(node.prefix!.text, 'p');
      expect(node.name.text, 'Map');
      expect(node.questionOffset, text.length - 1);
      final arguments = node.typeArguments!;
      expect(arguments.text, '<String?, List<int>>');
      expect(arguments.arguments.first.isNullable, isTrue);
      final list = arguments.arguments.last as NamedTypeAnnotation;
      expect(list.typeArguments!.text, '<int>');
      expect(list.end, text.length - 2);
      expect(() => arguments.arguments.clear(), throwsUnsupportedError);
      for (final name in [
        'void',
        'dynamic',
        'Never',
        'Function',
        'await',
        'type',
      ]) {
        expect((type(name) as NamedTypeAnnotation).name.text, name);
      }
    },
  );

  test(
    'parses function types, type parameters, bounds and parameter groups',
    () {
      final node = type(
        'R? Function<T extends Map<String, List<T>>, U>('
        'T value, {required U other, String? label,})?',
      ) as FunctionTypeAnnotation;
      expect(node.returnType!.text, 'R?');
      expect(node.isNullable, isTrue);
      expect(node.typeParameters!.parameters.map((p) => p.name.text), [
        'T',
        'U',
      ]);
      expect(
        node.typeParameters!.parameters.first.bound!.text,
        'Map<String, List<T>>',
      );
      expect(node.typeParameters!.parameters.last.bound, isNull);
      expect(node.parameters.parameters.map((p) => p.kind), [
        FunctionTypeParameterKind.requiredPositional,
        FunctionTypeParameterKind.requiredNamed,
        FunctionTypeParameterKind.optionalNamed,
      ]);
      expect(node.parameters.parameters.map((p) => p.name!.text), [
        'value',
        'other',
        'label',
      ]);
      final optional = type(
        'void Function(int, [String, bool flag,])',
      ) as FunctionTypeAnnotation;
      expect(optional.parameters.parameters.map((p) => p.kind), [
        FunctionTypeParameterKind.requiredPositional,
        FunctionTypeParameterKind.optionalPositional,
        FunctionTypeParameterKind.optionalPositional,
      ]);
      expect(optional.parameters.parameters[1].name, isNull);
      expect((type('Function()') as FunctionTypeAnnotation).returnType, isNull);
      final covariant = type(
        'void Function(covariant int x, String z, {required covariant int y})',
      ) as FunctionTypeAnnotation;
      expect(covariant.parameters.parameters.map((p) => p.isCovariant), [
        true,
        false,
        true,
      ]);
      expect(covariant.parameters.parameters.first.text, 'covariant int x');
      expect((type('get.T') as NamedTypeAnnotation).prefix!.text, 'get');
      final chain =
          type('int Function() Function(String)?') as FunctionTypeAnnotation;
      expect(chain.returnType, isA<FunctionTypeAnnotation>());
      expect(chain.returnType!.isNullable, isFalse);
    },
  );

  test('keeps positional and named record type fields in source order', () {
    final node = type(
      '(int x, List<String>, {bool ready, Function() action,})?',
    ) as RecordTypeAnnotation;
    expect(node.positionalFields.map((f) => f.name?.text), ['x', null]);
    expect(node.namedFields!.fields.map((f) => f.name.text), [
      'ready',
      'action',
    ]);
    expect(node.namedFields!.text, '{bool ready, Function() action,}');
    expect(node.isNullable, isTrue);
    expect((type('()') as RecordTypeAnnotation).childCount, 0);
    expect(
      (type(
        '(int,)',
      ) as RecordTypeAnnotation).positionalFields.single.type.text,
      'int',
    );
    expect(
      (type('({int x})') as RecordTypeAnnotation).positionalFields,
      isEmpty,
    );
  });

  test(
    'retains type variable, function parameter and record field metadata',
    () {
      for (final text in [
        'Function<@tag T>()',
        'int Function(@tag int x)',
        '(@tag int,)',
        '({@tag int x})',
        'T Function<@A(() => 1) T extends Object>({@B() required T x})',
      ]) {
        final result = parseType(text);
        expect(result.diagnostics, isEmpty, reason: text);
        expect(walk(result.node).whereType<Annotation>(), isNotEmpty);
      }
      final function =
          parseType('int Function(@tag int x)').node as FunctionTypeAnnotation;
      expect(
        function.parameters.parameters.single.metadata.single.text,
        '@tag',
      );
      final record = parseType('({@tag int x})').node as RecordTypeAnnotation;
      expect(record.namedFields!.fields.single.metadata.single.text, '@tag');
      expect(parseType('List<@tag int>').hasErrors, isTrue);
      expect(parseType('Function<@A( T>()').hasErrors, isTrue);
    },
  );

  test('rejects malformed type grammar', () {
    for (final text in [
      '',
      'void?',
      'void<int>',
      'void.x',
      'List<>',
      'List<int,>',
      'Map<A,',
      'Function<int>',
      'Function<T,>()',
      'Function<T extends>()',
      'Function<T extends void>()',
      'Function<dynamic>()',
      'Function<Function>()',
      'Function<as>()',
      'int Function([])',
      'int Function({})',
      'int Function([int)',
      'int Function([int,)',
      'int Function({int x)',
      'int Function([int],)',
      'int Function({int x},)',
      'int Function({int})',
      'int Function(required int x)',
      'int Function([required int x])',
      'int Function([int], {int x})',
      'int Function(int x = 1)',
      '(int)',
      '({})',
      '(int, {})',
      '({int x},)',
      '(int, {String x},)',
      '(int x int y)',
      '(int, {String})',
      'T??',
      'abstract',
      'get',
    ]) {
      expect(parseType(text).hasErrors, isTrue, reason: text);
    }
    final missing = parseType('List<');
    expect(missing.node, isA<MissingTypeAnnotation>());
    expect(missing.node.start, missing.node.end);
  });

  test('parses deeply nested type arguments inside type metadata', () {
    const depth = 5000;
    for (final (opening, closing) in [
      ('void Function(@A<', '>() int value)'),
      ('Function<@A<', '>() T>()'),
      ('(@A<', '>() int,)'),
    ]) {
      final text = '${opening * depth}int${closing * depth}';
      final input = scan(SourceFile(Uri.parse('memory:metadata'), text));
      final tokens = [...input.tokens];
      final result = parseTypeAnnotation(input);
      expect(result.diagnostics, isEmpty);
      expect(result.node.text, text);
      expect(walk(result.node).whereType<Annotation>(), hasLength(depth));
      expect(input.tokens, orderedEquals(tokens));
      expect(
        walk(result.node).every((n) => identical(n.source, input.source)),
        isTrue,
      );
      final invalid = parseType('${opening * depth}${closing * depth}');
      expect(invalid.hasErrors, isTrue);
      expect(invalid.node, isA<MissingTypeAnnotation>());
    }
  });

  test('retains types nested through annotation argument expressions', () {
    for (final (opening, closing) in [
      ('void Function(@A(const B<', '>()) int value)'),
      ('void Function(@A(f<', '>()) int value)'),
      ('void Function(@A(null as ', ') int value)'),
      ('void Function(@A((', ' value) => 0) int outer)'),
    ]) {
      final text = '${opening * 8}int${closing * 8}';
      final node = type(text);
      expect(node.text, text);
      expect(walk(node).whereType<Annotation>(), hasLength(8));
    }
  });

  test('type metadata belongs only to the following parameter or field', () {
    final variables =
        type('Function<@A<int>() T, U>()') as FunctionTypeAnnotation;
    expect(
      variables.typeParameters!.parameters.first.metadata.single.text,
      '@A<int>()',
    );
    expect(variables.typeParameters!.parameters.last.metadata, isEmpty);
    final function = type(
      'void Function(@A<int>() int x, String y)',
    ) as FunctionTypeAnnotation;
    expect(
      function.parameters.parameters.first.metadata.single.text,
      '@A<int>()',
    );
    expect(function.parameters.parameters.last.metadata, isEmpty);
    final record = type('(@A<int>() int, String)') as RecordTypeAnnotation;
    expect(record.positionalFields.first.metadata.single.text, '@A<int>()');
    expect(record.positionalFields.last.metadata, isEmpty);
  });

  test('splits closing angles locally and preserves scanner snapshots', () {
    final input = scan(
      SourceFile(Uri.parse('memory:tokens'), 'Map<A, B<C<D>>>'),
    );
    final tokens = [...input.tokens];
    final before = tokens
        .map((t) => (t.kind, t.start, t.end, t.lexeme))
        .toList();
    for (var i = 0; i < 2; i++) {
      final result = parseTypeAnnotation(input);
      expect(result.hasErrors, isFalse);
      expect(
        walk(result.node).every((n) => identical(n.source, input.source)),
        isTrue,
      );
    }
    expect(input.tokens, orderedEquals(tokens));
    expect(input.tokens.map((t) => (t.kind, t.start, t.end, t.lexeme)), before);
    expect(input.tokens.any((t) => t.kind == .unsignedShiftRight), isTrue);
  });

  test('parses generic calls and function values without resolving names', () {
    final call =
        parsed('f<Map<A, List<B>>>(x, named: y)') as InvocationExpression;
    expect(call.callee.text, 'f');
    expect(call.typeArguments!.text, '<Map<A, List<B>>>');
    expect(call.arguments.arguments.map((a) => a.value.text), ['x', 'y']);
    final value = parsed('f<int>') as TypeInstantiationExpression;
    expect(value.expression.text, 'f');
    expect(value.typeArguments.arguments.single.text, 'int');
    final parenthesized = parsed('(f<int>)(x)') as InvocationExpression;
    expect(parenthesized.typeArguments, isNull);
    expect(
      (parenthesized.callee as ParenthesizedExpression).expression,
      isA<TypeInstantiationExpression>(),
    );
    expect(
      parsed('f<(int,), void Function()>'),
      isA<TypeInstantiationExpression>(),
    );
    final named = parsed('C<int>.named()') as InvocationExpression;
    expect(
      (named.callee as PropertyAccessExpression).target,
      isA<TypeInstantiationExpression>(),
    );
  });

  test('disambiguates type arguments from comparisons and shifts', () {
    final generic = parsed('f(a<b,c>(d))') as InvocationExpression;
    expect(generic.arguments.arguments, hasLength(1));
    expect(
      (generic.arguments.arguments.single.value as InvocationExpression)
          .typeArguments!
          .arguments,
      hasLength(2),
    );
    final comparison = parsed('f(a<b,c>-d)') as InvocationExpression;
    expect(comparison.arguments.arguments, hasLength(2));
    expect(shape(comparison.arguments.arguments.first.value), '(< a b)');
    expect(shape(comparison.arguments.arguments.last.value), '(> c (- d))');
    expect(shape(parsed('a < b >> c')), '(< a (>> b c))');
    expect(shape(parsed('a < b >>> c')), '(< a (>>> b c))');
    for (final text in [
      'f<T> + x',
      'f<T>!',
      'f<T>?.x',
      'f<T>[0]',
      'f<A<B>>=x',
      'f<A<B>>>x',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    final input = scan(SourceFile(Uri.parse('memory:rollback'), 'f<A<B>>=x'));
    final tokens = [...input.tokens];
    expect(parseExpression(input).hasErrors, isTrue);
    expect(input.tokens, orderedEquals(tokens));
  });

  test('binds type tests and casts at relational precedence', () {
    final cast = parsed('a + b as T') as CastExpression;
    expect(shape(cast.expression), '(+ a b)');
    expect(cast.type.text, 'T');
    final test = parsed('a < b is! List<T?>') as TypeTestExpression;
    expect(test.isNegated, isTrue);
    expect(shape(test.expression), '(< a b)');
    expect(test.type.text, 'List<T?>');
    final comparison = parsed('a is T < b') as BinaryExpression;
    expect(comparison.left, isA<TypeTestExpression>());
    final conditional = parsed('a is T ? b : c') as ConditionalExpression;
    expect(
      (conditional.condition as TypeTestExpression).type.isNullable,
      isFalse,
    );
    expect((parsed('a is T?') as TypeTestExpression).type.isNullable, isTrue);
    final nullable = parsed('a is T? ? b : c') as ConditionalExpression;
    expect((nullable.condition as TypeTestExpression).type.isNullable, isTrue);
    final function = parsed('a as T? Function()') as CastExpression;
    expect(
      (function.type as FunctionTypeAnnotation).returnType!.isNullable,
      isTrue,
    );
    expect(parsed('(a as T).x'), isA<PropertyAccessExpression>());
    expect(parsed('a as void Function()'), isA<CastExpression>());
    for (final text in [
      'a as T + b',
      'a as T as U',
      'a is T is U',
      'a is void',
      'a as void',
      'a is T?[0]',
      'a as T()',
      'a as T!',
      'a < b is T < c',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
  });

  test('keeps operators remaining after type closing angles', () {
    for (final (text, operator, writtenType) in [
      ('a as List<int>> b', BinaryOperator.greater, 'List<int>'),
      ('a as List<int>>= b', BinaryOperator.greaterEqual, 'List<int>'),
      (
        'a as List<List<int>>>= b',
        BinaryOperator.greaterEqual,
        'List<List<int>>',
      ),
    ]) {
      final input = scan(SourceFile(Uri.parse('memory:suffix'), text));
      final tokens = [...input.tokens];
      final result = parseExpression(input);
      expect(result.hasErrors, isFalse, reason: text);
      final binary = result.node as BinaryExpression;
      expect(binary.op, operator);
      expect((binary.left as CastExpression).type.text, writtenType);
      expect(binary.right.text, 'b');
      expect(input.tokens, orderedEquals(tokens));
    }
  });

  test('handles deep types and failed generic trials without recursion', () {
    const depth = 12000;
    for (final text in [
      '${'List<' * depth}int${'>' * depth}',
      '${'(' * depth}int${',)' * depth}',
      '${'Function(' * depth}int${')' * depth}',
      'int${' Function()' * depth}',
    ]) {
      final node = type(text);
      expect(node.text, text);
      expect(walk(node).length, greaterThan(depth));
    }
    expect(parse('${'a < ' * depth}b').hasErrors, isTrue);
    expect(parse('a${' as T' * depth}').hasErrors, isTrue);
    final input = '${'a<' * depth}b${'>' * depth} + c';
    expect(parse(input).hasErrors, isTrue);
  });

  test(
    'malformed types keep diagnostics and nodes in their source snapshot',
    () {
      final random = Random(8103);
      const fragments = [
        'T',
        'void',
        'Function',
        'extends',
        'required',
        '(',
        ')',
        '{',
        '}',
        '[',
        ']',
        '<',
        '>',
        '>>',
        '>>=',
        '>>>',
        '>>>=',
        '?',
        '??',
        ',',
        '.',
        '@',
        ';',
        '`',
      ];
      for (var i = 0; i < 1200; i++) {
        final text = List.generate(
          random.nextInt(30),
          (_) => fragments[random.nextInt(fragments.length)],
        ).join(' ');
        final input = scan(SourceFile(Uri.parse('memory:malformed'), text));
        final tokens = [...input.tokens];
        for (final result in [
          parseTypeAnnotation(input),
          parseExpression(input),
        ]) {
          for (final node in walk(result.node)) {
            expect(node.source, same(input.source));
            expect(node.start, inInclusiveRange(0, text.length));
            expect(node.end, inInclusiveRange(node.start, text.length));
          }
          for (final diagnostic in result.diagnostics) {
            expect(diagnostic.span!.source, same(input.source));
          }
        }
        expect(input.tokens, orderedEquals(tokens));
      }
    },
  );
}
