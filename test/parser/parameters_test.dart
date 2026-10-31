import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

ParseResult<FormalParameterList> parse(String text) => parseFormalParameterList(
  scan(SourceFile(Uri.parse('memory:parameters'), text)),
);

FormalParameterList parsed(String text) {
  final result = parse(text);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text.length < 200 ? text : '${text.length} characters',
  );
  return result.node;
}

void main() {
  test('keeps required, optional and named parameters in source order', () {
    final positional = parsed('(x, String name, [int count = 2, fallback,])');
    expect(positional.parameters.map((p) => p.kind), [
      FormalParameterKind.requiredPositional,
      FormalParameterKind.requiredPositional,
      FormalParameterKind.optionalPositional,
      FormalParameterKind.optionalPositional,
    ]);
    expect(positional.parameters.first.type, isNull);
    expect(positional.parameters[1].type!.text, 'String');
    expect(positional.parameters[2].defaultClause!.text, '= 2');
    expect(positional.parameters.last.defaultClause, isNull);
    expect(() => positional.parameters.clear(), throwsUnsupportedError);
    final named = parsed(
      '({required String name, int count = 2, flag: true,})',
    );
    expect(named.parameters.first.kind, FormalParameterKind.requiredNamed);
    expect(named.parameters.last.kind, FormalParameterKind.optionalNamed);
    expect(
      named.parameters.last.defaultClause!.separator,
      ParameterDefaultSeparator.colon,
    );
    expect(parsed('()').parameters, isEmpty);
  });

  test('retains receiver prefixes and declaring modifiers without binding', () {
    final parameters = parsed(
      '(covariant num value, int this.field, {super.flag, final int count = 1, var item})',
    ).parameters;
    expect(parameters[0].isCovariant, isTrue);
    expect(parameters[1].prefix, ParameterPrefix.thisKeyword);
    expect(parameters[1].name.text, 'field');
    expect(parameters[2].prefix, ParameterPrefix.superKeyword);
    expect(parameters[3].keyword, VariableKeyword.finalKeyword);
    expect(parameters[4].keyword, VariableKeyword.varKeyword);
  });

  test('distinguishes omitted types from named, record and function types', () {
    final parameters = parsed(
      '(int, p.Type<T>? value, (int, {String name}) record, void Function(int) callback)',
    ).parameters;
    expect(parameters.first.name.text, 'int');
    expect(parameters.first.type, isNull);
    expect(parameters[1].type!.text, 'p.Type<T>?');
    expect(parameters[2].type, isA<RecordTypeAnnotation>());
    expect(parameters[3].type, isA<FunctionTypeAnnotation>());
    expect(
      parsed('(required, covariant, late)').parameters.map((p) => p.name.text),
      ['required', 'covariant', 'late'],
    );
  });

  test('retains nested function-form parameters and generic bounds', () {
    final parameter = parsed(
      '(int apply<T extends List<int>>(T item, void visit(String value))?)',
    ).parameters.single;
    expect(parameter.type!.text, 'int');
    final suffix = parameter.functionSuffix!;
    expect(suffix.typeParameters!.parameters.single.bound!.text, 'List<int>');
    expect(suffix.questionOffset, parameter.end - 1);
    expect(
      suffix
          .parameters
          .parameters
          .last
          .functionSuffix!
          .parameters
          .parameters
          .single
          .type!
          .text,
      'String',
    );
    expect(
      parsed('(void f(int))')
          .parameters
          .single
          .functionSuffix!
          .parameters
          .parameters
          .single
          .type,
      isNull,
    );
  });

  test('distinguishes function-form parameters named Function from types', () {
    for (final (text, returnType) in [
      ('(int Function(int value))', 'int'),
      ('({required int Function(int value)})', 'int'),
      ('([int Function(int value)?])', 'int'),
      ('(T Function<T extends Object>(T value))', 'T'),
      ('((int, String) Function(int value))', '(int, String)'),
      ('(int Function(int) Function(int value))', 'int Function(int)'),
      ('(int Function(int)? Function(int value)?)', 'int Function(int)?'),
    ]) {
      final parameter = parsed(text).parameters.single;
      expect(parameter.type!.text, returnType, reason: text);
      expect(parameter.name.text, 'Function', reason: text);
      final suffix = parameter.functionSuffix!;
      expect(suffix.parameters.parameters.single.name.text, 'value');
      expect(suffix.questionOffset != null, text.contains('value)?'));
    }
    final nested = parsed('(int outer(int Function(int value)))')
        .parameters
        .single
        .functionSuffix!
        .parameters
        .parameters
        .single;
    expect(nested.name.text, 'Function');
    expect(nested.type!.text, 'int');
    expect(
      nested.functionSuffix!.parameters.parameters.single.name.text,
      'value',
    );
    final typed = parsed('(int Function(int value) Function)')
        .parameters
        .single;
    expect(typed.name.text, 'Function');
    expect(typed.type, isA<FunctionTypeAnnotation>());
    expect(typed.functionSuffix, isNull);
  });

  test('retains metadata names, arguments and their original positions', () {
    final parameter = parsed(
      '(@tag @p.Mark<int>.named(1, label: "yes") int value)',
    ).parameters.single;
    expect(parameter.metadata, hasLength(2));
    expect(parameter.metadata.first.arguments, isNull);
    final annotation = parameter.metadata.last;
    expect(annotation.name.map((n) => n.text), ['p', 'Mark']);
    expect(annotation.typeArguments!.text, '<int>');
    expect(annotation.constructorName!.text, 'named');
    expect(annotation.arguments!.arguments.map((a) => a.text), [
      '1',
      'label: "yes"',
    ]);
    expect(parameter.type!.text, 'int');
    expect(walk(parameter).whereType<Annotation>(), hasLength(2));
  });

  test('distinguishes annotation arguments and a following record type', () {
    for (final gap in [' ', '/* comment */']) {
      final parameter = parsed('(@tag$gap(int, String) value)')
          .parameters
          .single;
      expect(parameter.metadata.single.arguments, isNull);
      expect(parameter.type, isA<RecordTypeAnnotation>());
    }
    final parameter = parsed('(@tag(int, String) value)').parameters.single;
    expect(parameter.metadata.single.arguments!.arguments, hasLength(2));
    expect(parameter.type, isNull);
    expect(parse('(@Mark<int> () value)').hasErrors, isTrue);
    expect(parse('(@p.Mark.named<int>() value)').hasErrors, isTrue);
  });

  test('leaves documentation comments in the scan result', () {
    final input = scan(
      SourceFile(
        Uri.parse('memory:comment'),
        '(/// Parameter documentation.\n @tag int value)',
      ),
    );
    final result = parseFormalParameterList(input);
    expect(result.hasErrors, isFalse);
    expect(input.comments.single.lexeme, '/// Parameter documentation.');
    expect(result.node.parameters.single.text, '@tag int value');
  });

  test('distinguishes modifier names from modifiers before record types', () {
    for (final word in ['required', 'covariant', 'late', 'static']) {
      final parameter = parsed('($word())').parameters.single;
      expect(parameter.name.text, word);
      expect(parameter.functionSuffix, isNotNull);
    }
    final parameter = parsed('({required covariant (int, String)? value})')
        .parameters
        .single;
    expect(parameter.kind, FormalParameterKind.requiredNamed);
    expect(parameter.isCovariant, isTrue);
    expect(parameter.type!.isNullable, isTrue);
    expect(parse('({covariant required value})').hasErrors, isTrue);
    expect(parse('(final covariant value)').hasErrors, isTrue);
    expect(parse('(void f(final value))').hasErrors, isTrue);
  });

  test(
    'uses ordinary expression syntax for defaults without evaluating them',
    () {
      final parameter = parsed('({value = a?[i] : const C(1),})')
          .parameters
          .single;
      expect(parameter.defaultClause!.value, isA<ConditionalExpression>());
      expect(
        parsed('({value = throw problem})')
            .parameters
            .single
            .defaultClause!
            .value,
        isA<ThrowExpression>(),
      );
      expect(
        parsed('({required value = 1})').parameters.single.defaultClause,
        isNotNull,
      );
    },
  );

  test(
    'reports invalid groups, modifiers, suffixes and default separators',
    () {
      for (final text in [
        '',
        '(',
        '(x',
        '([])',
        '({})',
        '(x,[y],)',
        '(x,{y},)',
        '([x],{y})',
        '(x=1)',
        '([x:1])',
        '(required x)',
        '(const x)',
        '(late x)',
        '(final var x)',
        '(void f([x=1]))',
        '(void Function([x=1]))',
        '(void f<T,>(T value))',
        '(void Function<T,>(T value))',
        '(void f<T extends void>(T value))',
        '(void Function<T extends void>(T value))',
        '(int f<T>)',
        '(this x)',
        '(@)',
      ]) {
        expect(parse(text).hasErrors, isTrue, reason: text);
      }
      final recovered = parse('(int x String y)');
      expect(recovered.hasErrors, isTrue);
      expect(recovered.node.parameters.map((p) => p.name.text), ['x', 'y']);
    },
  );

  test('handles deeply nested function-form parameters iteratively', () {
    const depth = 12000;
    for (final head in ['void f(', 'void Function(', 'void Function<T>(']) {
      final text = '(${head * depth}int x${")" * depth})';
      final tree = parsed(text);
      expect(tree.text, text);
      expect(walk(tree).whereType<FunctionParameterSuffix>(), hasLength(depth));
    }
  });

  test('recovers malformed parameters without modifying input or ranges', () {
    final random = Random(80120);
    const fragments = [
      '(',
      ')',
      '{',
      '}',
      '[',
      ']',
      '[]',
      '<',
      '>',
      '>>',
      '>>=',
      ',',
      ';',
      '?',
      '.',
      '=',
      ' :',
      '@',
      'T',
      'x',
      '1',
      'var',
      'final',
      'const',
      'late',
      'required',
      'covariant',
      'this',
      'super',
      'extends',
      'void',
      'Function',
      '=>',
      'throw',
    ];
    for (var i = 0; i < 3000; i++) {
      final text = [
        for (var n = random.nextInt(40); n > 0; n--)
          fragments[random.nextInt(fragments.length)],
      ].join(' ');
      final input = scan(
        SourceFile(Uri.parse('memory:malformed-parameters'), text),
      );
      final tokens = [...input.tokens];
      final result = parseFormalParameterList(input);
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
  });
}
