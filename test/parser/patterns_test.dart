import 'dart:math';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'compilation_units_test.dart' as units;
import 'fixtures.dart' as expressions;

ParseResult<DartPattern> parse(
  String text, {
  PatternContext context = .matching,
}) => parsePattern(
  scan(SourceFile(Uri.parse('memory:pattern'), text)),
  context: context,
);

DartPattern parsed(String text, {PatternContext context = .matching}) {
  final result = parse(text, context: context);
  expect(
    result.diagnostics.map((d) => '${d.code}: ${d.span?.text}'),
    isEmpty,
    reason: text,
  );
  expect(result.node.text, text);
  return result.node;
}

void main() {
  test('retains variable keywords, types, identifiers and wildcards', () {
    expect(parsed('name'), isA<IdentifierPattern>());
    expect(parsed('_'), isA<WildcardPattern>());
    final variable = parsed('final List<int?> value') as VariablePattern;
    expect(variable.keyword, PatternVariableKeyword.finalKeyword);
    expect(variable.type!.text, 'List<int?>');
    expect(variable.name.text, 'value');
    expect(
      (parsed('var _') as WildcardPattern).keyword,
      PatternVariableKeyword.varKeyword,
    );
    expect((parsed('int _') as WildcardPattern).type!.text, 'int');
    expect(
      (parsed('(int, String) pair') as VariablePattern).type,
      isA<RecordTypeAnnotation>(),
    );
    expect(
      (parsed('void Function(int) callback') as VariablePattern).type,
      isA<FunctionTypeAnnotation>(),
    );
    expect(
      parsed('[first, int second]', context: .declaration),
      isA<ListPattern>(),
    );
    expect(parsed('[first, second]', context: .assignment), isA<ListPattern>());
  });

  test('retains constant and relational operands without evaluating them', () {
    for (final text in [
      '1',
      '-1.5',
      'true',
      'null',
      "'a' 'b'",
      '#symbol',
      'prefix.Enum.value',
      'const C.named(1)',
      'const <int>[1, 2]',
      'const {1: 2}',
      'const (1 + 2)',
      '.value',
    ]) {
      expect(parsed(text), isA<ConstantPattern>(), reason: text);
    }
    final explicit = parsed('const (1 + 2)') as ConstantPattern;
    expect(explicit.hasConstKeyword, isTrue);
    expect(explicit.expression, isA<ParenthesizedExpression>());
    final relation = parsed('>= 1 + 2 * 3') as RelationalPattern;
    expect(relation.op, RelationalPatternOperator.greaterEqual);
    expect(relation.operand, isA<BinaryExpression>());
    expect(
      (parsed('< 10') as RelationalPattern).op,
      RelationalPatternOperator.less,
    );
  });

  test('preserves logical precedence and unary pattern boundaries', () {
    final logical = parsed('>= 0 && < 10 || 42') as LogicalPattern;
    expect(logical.op, LogicalPatternOperator.or);
    expect(logical.left, isA<LogicalPattern>());
    expect(logical.right, isA<ConstantPattern>());
    expect(parsed('var value as int'), isA<CastPattern>());
    expect(parsed('var value?'), isA<NullCheckPattern>());
    expect(parsed('(var value?)!'), isA<NullAssertPattern>());
    expect(parsed('(var value)'), isA<ParenthesizedPattern>());
  });

  test(
    'retains typed lists, maps, records, rest elements and object fields',
    () {
      final list = parsed('<int>[first, ...var middle, last]') as ListPattern;
      expect(list.typeArguments!.text, '<int>');
      expect(list.elements[1], isA<RestPatternElement>());
      final map = parsed('<String, int>{"key": var value}') as MapPattern;
      expect(map.elements.first, isA<MapPatternEntry>());
      expect(map.elements, hasLength(1));
      final record = parsed('(var first, :final second)') as RecordPattern;
      expect(
        record.fields[1],
        isA<NamedPatternField>().having((f) => f.name, 'inferred name', isNull),
      );
      final object =
          parsed('prefix.Point<int>(x: var x, :final y)') as ObjectPattern;
      expect(object.type.text, 'prefix.Point<int>');
      expect(object.fields, hasLength(2));
      expect(parsed('()'), isA<RecordPattern>());
      expect(parsed('(value,)'), isA<RecordPattern>());
      expect(parsed('[]'), isA<ListPattern>());
      expect(parsed('{}'), isA<MapPattern>());
      final interleaved = parsed('(a: var a, var b)') as RecordPattern;
      expect(interleaved.fields.first, isA<NamedPatternField>());
      expect(interleaved.fields.last, isA<VariablePattern>());
    },
  );

  test('diagnoses invalid variable contexts and malformed pattern syntax', () {
    for (final text in [
      'var int x',
      'var x?!',
      '>= 1?',
      'when',
      'as',
      '[...,...]',
      '{...var rest}',
      '{"key": _, ...}',
      '{..., "key": _}',
      'Point(var x)',
      'const .value',
      '1 + 2',
      '[',
      '(a,',
    ]) {
      expect(parse(text).hasErrors, isTrue, reason: text);
    }
    expect(parse('[var x]', context: .declaration).hasErrors, isTrue);
    expect(parse('[int x]', context: .assignment).hasErrors, isTrue);
    expect(parse('[final x]', context: .assignment).hasErrors, isTrue);
  });

  test('parses pattern declarations, assignments and nested initializer expressions', () {
    final unit = units.parsed('''
void f(value) {
  var (first, second) = value;
  final <String, int>{'key': found} = value;
  @deprecated final (int, int) pair = value;
  @deprecated var [head, ...tail] = value;
  (first, second) = (second, first);
  [first, ...tail] = value;
  {'key': first} = value;
  Point(x: first) = value;
  []=value;
}
''');
    final body =
        (unit.members.single as TopLevelFunctionDeclaration).body
            as BlockStatement;
    final statements = body.statements;
    expect(statements[0], isA<PatternVariableDeclarationStatement>());
    expect(statements[2], isA<VariableDeclarationStatement>());
    expect(
      (statements[3] as PatternVariableDeclarationStatement)
          .declaration
          .metadata
          .single
          .text,
      '@deprecated',
    );
    for (final statement in statements.skip(4).cast<ExpressionStatement>()) {
      expect(statement.expression, isA<PatternAssignmentExpression>());
    }
  });

  test('pattern assignment requires an assignment-expression position', () {
    expect(expressions.parse('1 + [x] = value').hasErrors, isTrue);
    expect(expressions.parse('![x] = value').hasErrors, isTrue);
    expressions.parsed('f([x] = value)');
    expressions.parsed('1 + ([x] = value)');
    expressions.parsed('flag ? [x] = first : [x] = second');
    expressions.parsed(
      'flag ? [for (@deprecated int? x = null; x != null; x = x) x] : []',
    );
  });

  test('missing patterns use zero-width recovery nodes', () {
    final result = parse('');
    expect(result.hasErrors, isTrue);
    expect(result.node, isA<MissingPattern>());
    expect(result.node.start, result.node.end);
  });

  test('parses guarded if-case statements and collection elements', () {
    final unit = units.parsed('''
void f(value) {
  if (value case [final x, ...] when x > 0) use(x); else fallback();
  final result = [if (value case (:var x, :var y) when x != y) x else y];
}
''');
    final body =
        ((unit.members.single as TopLevelFunctionDeclaration).body
            as BlockStatement);
    final statement = body.statements.first as IfStatement;
    expect(statement.casePattern, isA<GuardedPattern>());
    expect(statement.elseStatement, isA<ExpressionStatement>());
    final collection =
        (body.statements[1] as VariableDeclarationStatement)
                .variables
                .declarations
                .single
                .initializer
            as CollectionExpression;
    final element = collection.elements.single as IfElement;
    expect(element.casePattern, isA<GuardedPattern>());
    expect(element.elseElement, isA<IdentifierExpression>());
  });

  test(
    'parses pattern for and for-in headers with metadata and async context',
    () {
      units.parsed('''
Future<void> f(values) async {
  for (var (x, y) in values) use(x, y);
  for (@deprecated final [x, ...rest] in values) use(x);
  for (var (x, y) = (0, 1); x < 10; x++, y++) use(x, y);
  await for (final (:x, :y) in values) use(x, y);
  final result = [for (final (x,y) in values) if (x case > 0) y];
  final more = [for (@deprecated var i = 0; i < 3; i++) i];
}
''');
    },
  );

  test(
    'switch expression composes with calls, collections, guards and closures',
    () {
      final expression = expressions.parsed(
        'f(switch (value) { const (1 + 2) => () => 3, [var x] when x > 0 => x, _ => switch (other) { _ => 0 } })',
      ) as InvocationExpression;
      final value =
          expression.arguments.arguments.single.value as SwitchExpression;
      expect(value.cases, hasLength(3));
      expect(value.cases.first.value, isA<FunctionExpression>());
      expect(value.cases[1].pattern, isA<GuardedPattern>());
      expect(value.cases.last.value, isA<SwitchExpression>());
      expressions.parsed('[if (ready) switch (x) { _ => 1 } else 0]');
      expressions.parsed('[if (a) (b) else {}]');
      expressions.parsed('flag ? switch (x) { _ => 1 } : 0');
    },
  );

  test(
    'switch statement retains consecutive cases, labels, guards and default',
    () {
      final result = parseStatement(
        scan(
          SourceFile(Uri.parse('memory:switch'), '''
switch (value) {
  first: case 0:
  case 1: use(); break;
  case [var head, ...] when head > 0: continue first;
  default: fallback();
}
'''),
        ),
      );
      expect(result.diagnostics, isEmpty);
      final statement = result.node as SwitchStatement;
      expect(statement.members, hasLength(4));
      expect(statement.members.first.labels.single.name.text, 'first');
      expect(statement.members.first.statements, isEmpty);
      expect(statement.members[1].statements, hasLength(2));
      expect(statement.members[2].pattern, isA<GuardedPattern>());
      expect(statement.members.last.pattern, isNull);
    },
  );

  test('operator less is distinct from a generic method named operator', () {
    final unit = units.parsed(
      'abstract class C { bool operator <(C other); T operator<T>(T x) => x; }',
    );
    final members = (unit.members.single as ClassDeclaration).members;
    expect(
      (members.first as OperatorDeclaration).op,
      DeclaredOperator.lessThan,
    );
    expect((members.last as MethodDeclaration).name.text, 'operator');
  });

  test('inferred field names retain null-check and cast subpatterns', () {
    final pattern =
        parsed('C(:var value?, :final other as int)') as ObjectPattern;
    expect(
      (pattern.fields.first as NamedPatternField).pattern,
      isA<NullCheckPattern>(),
    );
    expect(
      (pattern.fields.last as NamedPatternField).pattern,
      isA<CastPattern>(),
    );
  });

  test('record return types follow member modifiers and grouped initializers precede bodies', () {
    units.parsed('''
class C {
  final int x;
  new(int value) : x = (((value + 1) << 8) | 3) { assert(x > 0); }
  static (int, int) decode(int value) => (value, value);
  external (int, int) externalPair();
}
''');
  });

  test('nested patterns and switches do not consume the native call stack', () {
    final pattern = parsed('${'[' * 1000}var value${']' * 1000}');
    expect(walk(pattern).whereType<ListPattern>(), hasLength(1000));
    final expression = expressions.parsed(
      '${'switch (x) { _ => ' * 1000}0${'}' * 1000}',
    );
    expect(walk(expression).whereType<SwitchExpression>(), hasLength(1000));
  });

  test(
    'malformed pattern and switch input terminates and retains source ranges',
    () {
      final random = Random(91);
      final tokens = [
        'var',
        'final',
        'x',
        'case',
        'when',
        '[',
        ']',
        '{',
        '}',
        '(',
        ')',
        ':',
        ',',
        '...',
        '?',
        '!',
        '=>',
        '&&',
        '||',
        '=',
        ';',
      ];
      for (var i = 0; i < 300; i++) {
        final text = List.generate(
          random.nextInt(24),
          (_) => tokens[random.nextInt(tokens.length)],
        ).join(' ');
        for (final result in [
          parse(text),
          units.parse('void f(x) { switch(x) { case $text } }'),
        ]) {
          for (final node in walk(result.node)) {
            expect(node.start, inInclusiveRange(0, node.source.length));
            expect(node.end, inInclusiveRange(node.start, node.source.length));
          }
        }
      }
    },
  );
}
