import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'keeps nested object, map, and list patterns without inferred fields',
    () {
      final f = SyntaxFixture(
        "Point<int>(:var x?, data: <String, Object>{'items': [final y!, ...var rest]})",
      );
      final x = VariablePattern(
        source: f.source,
        start: f.at('var x'),
        end: f.at('x?') + 1,
        keyword: .varKeyword,
        name: f.id('x'),
      );
      final checked = NullCheckPattern(
        source: f.source,
        start: x.start,
        end: x.end + 1,
        pattern: x,
      );
      final inferred = NamedPatternField(
        source: f.source,
        start: x.start - 1,
        end: checked.end,
        pattern: checked,
      );
      final y = VariablePattern(
        source: f.source,
        start: f.at('final y'),
        end: f.at('y!') + 1,
        keyword: .finalKeyword,
        name: f.id('y'),
      );
      final asserted = NullAssertPattern(
        source: f.source,
        start: y.start,
        end: y.end + 1,
        pattern: y,
      );
      final restName = VariablePattern(
        source: f.source,
        start: f.at('var rest'),
        end: f.at('rest') + 4,
        keyword: .varKeyword,
        name: f.id('rest'),
      );
      final rest = RestPatternElement(
        source: f.source,
        start: restName.start - 3,
        end: restName.end,
        pattern: restName,
      );
      final elements = <ListPatternElement>[asserted, rest];
      final list = ListPattern(
        source: f.source,
        start: f.at('['),
        end: f.at(']') + 1,
        elements: elements,
      );
      elements.clear();
      final entry = MapPatternEntry(
        source: f.source,
        start: f.at("'items'"),
        end: list.end,
        key: f.string("'items'"),
        value: list,
      );
      final map = MapPattern(
        source: f.source,
        start: f.at('<String'),
        end: f.at('}') + 1,
        typeArguments: TypeArgumentList(
          source: f.source,
          start: f.at('<String'),
          end: f.at('>{') + 1,
          arguments: [f.type('String'), f.type('Object')],
        ),
        elements: [entry],
      );
      final fields = <PatternField>[
        inferred,
        NamedPatternField(
          source: f.source,
          start: f.at('data:'),
          end: map.end,
          name: f.id('data'),
          pattern: map,
        ),
      ];
      final root = ObjectPattern(
        source: f.source,
        start: 0,
        end: f.source.length,
        type: NamedTypeAnnotation(
          source: f.source,
          start: 0,
          end: f.at('>') + 1,
          name: f.id('Point'),
          typeArguments: TypeArgumentList(
            source: f.source,
            start: f.at('<'),
            end: f.at('>') + 1,
            arguments: [f.type('int', from: f.at('<'))],
          ),
        ),
        fields: fields,
      );
      fields.clear();
      checkTree(root);
      expect(inferred.name, isNull);
      expect(inferred.text, ':var x?');
      expect(list.elements, [asserted, rest]);
      expect(root.fields.length, 2);
      expect(walk(root).whereType<Identifier>().map((n) => n.text), [
        'Point',
        'int',
        'x',
        'data',
        'String',
        'Object',
        'y',
        'rest',
      ]);
      expect(walk(root).where((n) => identical(n, x.name)).length, 1);
      expect(() => root.fields.clear(), throwsUnsupportedError);
      expect(() => list.elements.clear(), throwsUnsupportedError);
      expect(() => map.elements.clear(), throwsUnsupportedError);
    },
  );

  test(
    'preserves record field order, ambiguous names, casts, and wildcards',
    () {
      final f = SyntaxFixture('(a, named: int b, :var c as num, final int _)');
      final a = f.patternName('a');
      final b = VariablePattern(
        source: f.source,
        start: f.at('int b'),
        end: f.at('b,') + 1,
        type: f.type('int'),
        name: f.id('b'),
      );
      final c = VariablePattern(
        source: f.source,
        start: f.at('var c'),
        end: f.at('c as') + 1,
        keyword: .varKeyword,
        name: f.id('c'),
      );
      final cast = CastPattern(
        source: f.source,
        start: c.start,
        end: f.at('num') + 3,
        pattern: c,
        type: f.type('num'),
      );
      final wildcard = WildcardPattern(
        source: f.source,
        start: f.at('final'),
        end: f.at('_') + 1,
        keyword: .finalKeyword,
        type: f.type('int', from: f.at('final')),
      );
      final root = RecordPattern(
        source: f.source,
        start: 0,
        end: f.source.length,
        fields: [
          a,
          NamedPatternField(
            source: f.source,
            start: f.at('named:'),
            end: b.end,
            name: f.id('named'),
            pattern: b,
          ),
          NamedPatternField(
            source: f.source,
            start: c.start - 1,
            end: cast.end,
            pattern: cast,
          ),
          wildcard,
        ],
      );
      checkTree(root);
      expect(root.childAt(0), same(a));
      expect(root.childAt(3), same(wildcard));
      expect(walk(root).whereType<IdentifierPattern>(), [a]);
      expect(wildcard.keyword, PatternVariableKeyword.finalKeyword);
      expect(wildcard.type!.text, 'int');
      expect(
        walk(root).whereType<NamedPatternField>().map((n) => n.name?.text),
        ['named', null],
      );
    },
  );

  test('retains logical branches, relational operands, and parentheses', () {
    final f = SyntaxFixture('(>= low && < high) || == limit');
    final low = RelationalPattern(
      source: f.source,
      start: f.at('>='),
      end: f.at('low') + 3,
      op: .greaterEqual,
      operand: f.reference('low'),
    );
    final high = RelationalPattern(
      source: f.source,
      start: f.at('<'),
      end: f.at('high') + 4,
      op: .less,
      operand: f.reference('high'),
    );
    final conjunction = LogicalPattern(
      source: f.source,
      start: low.start,
      end: high.end,
      left: low,
      op: .and,
      right: high,
    );
    final grouped = ParenthesizedPattern(
      source: f.source,
      start: 0,
      end: f.at(')') + 1,
      pattern: conjunction,
    );
    final equal = RelationalPattern(
      source: f.source,
      start: f.at('=='),
      end: f.source.length,
      op: .equal,
      operand: f.reference('limit'),
    );
    final root = LogicalPattern(
      source: f.source,
      start: 0,
      end: f.source.length,
      left: grouped,
      op: .or,
      right: equal,
    );
    checkTree(root);
    expect(root.left, same(grouped));
    expect(grouped.pattern, same(conjunction));
    expect(
      walk(root).whereType<RelationalPattern>().map((n) => n.op.spelling),
      ['>=', '<', '=='],
    );
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'low',
      'high',
      'limit',
    ]);
  });

  test('keeps explicit constant-pattern syntax separate from evaluation', () {
    final f = SyntaxFixture('const (limit + 1)');
    final sum = f.binary(f.reference('limit'), .add, f.literal('1'));
    final expression = ParenthesizedExpression(
      source: f.source,
      start: f.at('('),
      end: f.source.length,
      expression: sum,
    );
    final root = ConstantPattern(
      source: f.source,
      start: 0,
      end: f.source.length,
      hasConstKeyword: true,
      expression: expression,
    );
    checkTree(root);
    expect(root.hasConstKeyword, isTrue);
    expect(root.expression.text, '(limit + 1)');
    expect(walk(root).whereType<Identifier>().single.text, 'limit');
  });

  test('preserves destructuring assignment targets without declaring them', () {
    final f = SyntaxFixture('(x, y) = pair()');
    final x = f.patternName('x');
    final y = f.patternName('y');
    final pattern = RecordPattern(
      source: f.source,
      start: 0,
      end: f.at(')') + 1,
      fields: [x, y],
    );
    final value = f.emptyCall('pair');
    final root = PatternAssignmentExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      pattern: pattern,
      value: value,
    );
    checkTree(root);
    expect(walk(root).whereType<VariablePattern>(), isEmpty);
    expect(walk(root).whereType<IdentifierPattern>(), [x, y]);
    expect(walk(root).whereType<InvocationExpression>(), [value]);
  });

  test('retains a typed list, omitted rest subpattern, and empty record', () {
    final f = SyntaxFixture('<Object>[_, ..., ()]');
    final wildcard = WildcardPattern(
      source: f.source,
      start: f.at('_'),
      end: f.at('_') + 1,
    );
    final rest = RestPatternElement(
      source: f.source,
      start: f.at('...'),
      end: f.at('...') + 3,
    );
    final empty = RecordPattern(
      source: f.source,
      start: f.at('()'),
      end: f.at('()') + 2,
      fields: [],
    );
    final root = ListPattern(
      source: f.source,
      start: 0,
      end: f.source.length,
      typeArguments: TypeArgumentList(
        source: f.source,
        start: 0,
        end: f.at('>') + 1,
        arguments: [f.type('Object')],
      ),
      elements: [wildcard, rest, empty],
    );
    checkTree(root);
    expect(root.childAt(0), same(root.typeArguments));
    expect(root.childAt(1), same(wildcard));
    expect(rest.pattern, isNull);
    expect(rest.childCount, 0);
    expect(empty.fields, isEmpty);
  });

  test('checks missing-pattern bounds, source identity, and field order', () {
    final f = SyntaxFixture('a b');
    final missing = MissingPattern(source: f.source, offset: f.source.length);
    checkTree(missing);
    expect(missing.text, isEmpty);
    expect(() => MissingPattern(source: f.source, offset: 4), throwsRangeError);
    expect(
      () => NullCheckPattern(
        source: f.source,
        start: 0,
        end: 3,
        pattern: SyntaxFixture('a b').patternName('a'),
      ),
      throwsArgumentError,
    );
    expect(
      () => LogicalPattern(
        source: f.source,
        start: 0,
        end: 3,
        left: f.patternName('b'),
        op: .and,
        right: f.patternName('a'),
      ),
      throwsArgumentError,
    );
    expect(
      () => NamedPatternField(
        source: f.source,
        start: 1,
        end: 3,
        name: f.id('a'),
        pattern: f.patternName('b'),
      ),
      throwsArgumentError,
    );
  });
}
