import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('type syntax', () {
    test('retains generic function types, bounds, names, and nullability', () {
      final type = functionTypeFixture();
      checkTree(type);
      expect(type.isNullable, isTrue);
      expect(type.returnType!.text, 'T');
      expect(
        type.typeParameters!.parameters.single.text,
        '@tag T extends p.Box<int?>',
      );
      expect(type.parameters.parameters.map((p) => p.kind), [
        FunctionTypeParameterKind.requiredPositional,
        FunctionTypeParameterKind.requiredNamed,
      ]);
      expect(walk(type).whereType<Identifier>().map((n) => n.text), [
        'T',
        'tag',
        'T',
        'p',
        'Box',
        'int',
        'T',
        'value',
        'String',
        'name',
      ]);
      expect(
        walk(type)
            .whereType<NamedTypeAnnotation>()
            .where((t) => t.isNullable)
            .single
            .text,
        'int?',
      );
    });

    test(
      'keeps omitted function return types and optional parameter kinds',
      () {
        for (final (text, kind) in [
          (
            'Function([int value])',
            FunctionTypeParameterKind.optionalPositional,
          ),
          ('Function({int value})', FunctionTypeParameterKind.optionalNamed),
        ]) {
          final f = SyntaxFixture(text);
          final parameter = FunctionTypeParameter(
            source: f.source,
            start: f.at('int'),
            end: f.at('value') + 5,
            kind: kind,
            type: f.type('int'),
            name: f.id('value'),
          );
          final node = FunctionTypeAnnotation(
            source: f.source,
            start: 0,
            end: text.length,
            parameters: FunctionTypeParameterList(
              source: f.source,
              start: f.at('('),
              end: text.length,
              parameters: [parameter],
            ),
          );
          checkTree(node);
          expect(node.returnType, isNull);
          expect(node.typeParameters, isNull);
          expect(node.isNullable, isFalse);
          expect(node.parameters.parameters.single.kind, kind);
        }
      },
    );

    test('retains metadata on named and unnamed function-type parameters', () {
      final f = SyntaxFixture(
        'int Function(@tag int, {@tag2 required String name})',
      );
      final node = FunctionTypeAnnotation(
        source: f.source,
        start: 0,
        end: f.source.length,
        returnType: f.type('int'),
        parameters: FunctionTypeParameterList(
          source: f.source,
          start: f.at('('),
          end: f.source.length,
          parameters: [
            FunctionTypeParameter(
              source: f.source,
              start: f.at('@tag'),
              end: f.at(','),
              metadata: [f.annotation('tag')],
              kind: .requiredPositional,
              type: f.type('int', from: f.at('(')),
            ),
            FunctionTypeParameter(
              source: f.source,
              start: f.at('@tag2'),
              end: f.at('}'),
              metadata: [f.annotation('tag2')],
              kind: .requiredNamed,
              type: f.type('String'),
              name: f.id('name'),
            ),
          ],
        ),
      );
      checkTree(node);
      expect(node.parameters.parameters.first.name, isNull);
      expect(walk(node).whereType<Identifier>().map((n) => n.text), [
        'int',
        'tag',
        'int',
        'tag2',
        'String',
        'name',
      ]);
    });

    test('retains record field metadata and positional and named fields', () {
      final f = SyntaxFixture('(@tag int first, {String name, bool active})?');
      final record = RecordTypeAnnotation(
        source: f.source,
        start: 0,
        end: f.source.length,
        questionOffset: f.source.length - 1,
        positionalFields: [
          PositionalRecordTypeField(
            source: f.source,
            start: 1,
            end: f.at(','),
            metadata: [f.annotation('tag')],
            type: f.type('int'),
            name: f.id('first'),
          ),
        ],
        namedFields: RecordTypeNamedFields(
          source: f.source,
          start: f.at('{'),
          end: f.at('}') + 1,
          fields: [
            NamedRecordTypeField(
              source: f.source,
              start: f.at('String'),
              end: f.at('name') + 4,
              type: f.type('String'),
              name: f.id('name'),
            ),
            NamedRecordTypeField(
              source: f.source,
              start: f.at('bool'),
              end: f.at('active') + 6,
              type: f.type('bool'),
              name: f.id('active'),
            ),
          ],
        ),
      );
      checkTree(record);
      expect(record.isNullable, isTrue);
      expect(walk(record).whereType<Identifier>().map((n) => n.text), [
        'tag',
        'int',
        'first',
        'String',
        'name',
        'bool',
        'active',
      ]);
    });

    test('retains unnamed positional fields and empty records', () {
      final f = SyntaxFixture('(int,)');
      final field = PositionalRecordTypeField(
        source: f.source,
        start: 1,
        end: 4,
        type: f.type('int'),
      );
      final record = RecordTypeAnnotation(
        source: f.source,
        start: 0,
        end: 6,
        positionalFields: [field],
      );
      checkTree(record);
      expect(field.name, isNull);
      expect(record.namedFields, isNull);
      final empty = SyntaxFixture('()');
      final emptyRecord = RecordTypeAnnotation(
        source: empty.source,
        start: 0,
        end: 2,
      );
      expect(walk(emptyRecord), [emptyRecord]);
    });
  });

  test('retains annotation arguments and expression operand order', () {
    final f = SyntaxFixture(
      '@p.Mark<int>.named(value: -1 + (2 * 3), ok: true ? p.flag : false)',
    );
    final negative = UnaryExpression(
      source: f.source,
      start: f.at('-1'),
      end: f.at('-1') + 2,
      op: .negate,
      operand: f.literal('1'),
    );
    final product = f.binary(f.literal('2'), .multiply, f.literal('3'));
    final parens = ParenthesizedExpression(
      source: f.source,
      start: product.start - 1,
      end: product.end + 1,
      expression: product,
    );
    final sum = f.binary(negative, .add, parens);
    final access = PropertyAccessExpression(
      source: f.source,
      start: f.at('p.flag'),
      end: f.at('p.flag') + 6,
      target: f.reference('p', f.at('true')),
      property: f.id('flag'),
    );
    final conditional = ConditionalExpression(
      source: f.source,
      start: f.at('true'),
      end: f.at('false') + 5,
      condition: f.literal('true', kind: .boolean),
      thenExpression: access,
      elseExpression: f.literal('false', kind: .boolean),
    );
    final annotation = Annotation(
      source: f.source,
      start: 0,
      end: f.source.length,
      name: [f.id('p'), f.id('Mark')],
      typeArguments: TypeArgumentList(
        source: f.source,
        start: f.at('<'),
        end: f.at('>') + 1,
        arguments: [f.type('int')],
      ),
      constructorName: f.id('named'),
      arguments: ArgumentList(
        source: f.source,
        start: f.at('('),
        end: f.source.length,
        arguments: [
          Argument(
            source: f.source,
            start: f.at('value'),
            end: sum.end,
            name: f.id('value'),
            value: sum,
          ),
          Argument(
            source: f.source,
            start: f.at('ok'),
            end: conditional.end,
            name: f.id('ok'),
            value: conditional,
          ),
        ],
      ),
    );
    checkTree(annotation);
    expect(walk(annotation).whereType<LiteralExpression>().map((n) => n.text), [
      '1',
      '2',
      '3',
      'true',
      'false',
    ]);
    expect(walk(annotation).whereType<Identifier>().map((n) => n.text), [
      'p',
      'Mark',
      'int',
      'named',
      'value',
      'ok',
      'p',
      'flag',
    ]);
    expect(walk(annotation).whereType<BinaryExpression>().map((n) => n.op), [
      BinaryOperator.add,
      BinaryOperator.multiply,
    ]);
  });

  test('retains calls with type arguments and positional arguments', () {
    final f = SyntaxFixture('f<int>(x)');
    final node = InvocationExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      callee: f.reference('f'),
      typeArguments: TypeArgumentList(
        source: f.source,
        start: 1,
        end: 6,
        arguments: [f.type('int')],
      ),
      arguments: ArgumentList(
        source: f.source,
        start: 6,
        end: 9,
        arguments: [
          Argument(source: f.source, start: 7, end: 8, value: f.reference('x')),
        ],
      ),
    );
    checkTree(node);
    expect(walk(node).whereType<Identifier>().map((n) => n.text), [
      'f',
      'int',
      'x',
    ]);
  });

  test('keeps constructor and prefixed-type name ambiguity until binding', () {
    final f = SyntaxFixture('const C.named(1)');
    final node = InstanceCreationExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      kind: .constKeyword,
      name: [f.id('C'), f.id('named')],
      arguments: ArgumentList(
        source: f.source,
        start: f.at('('),
        end: f.source.length,
        arguments: [
          Argument(
            source: f.source,
            start: f.at('1'),
            end: f.at('1') + 1,
            value: f.literal('1'),
          ),
        ],
      ),
    );
    checkTree(node);
    expect(node.kind, InstanceCreationKind.constKeyword);
    expect(node.constructorName, isNull);
    expect(walk(node).whereType<Identifier>().map((n) => n.text), [
      'C',
      'named',
    ]);
  });

  test('retains constructor names following explicit type arguments', () {
    final f = SyntaxFixture('new p.C<int>.named()');
    final node = InstanceCreationExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      kind: .newKeyword,
      name: [f.id('p'), f.id('C')],
      typeArguments: TypeArgumentList(
        source: f.source,
        start: f.at('<'),
        end: f.at('>') + 1,
        arguments: [f.type('int')],
      ),
      constructorName: f.id('named'),
      arguments: ArgumentList(
        source: f.source,
        start: f.at('('),
        end: f.source.length,
        arguments: [],
      ),
    );
    checkTree(node);
    expect(node.constructorName!.text, 'named');
    expect(walk(node).whereType<Identifier>().map((n) => n.text), [
      'p',
      'C',
      'int',
      'named',
    ]);
  });

  group('range and ownership contracts', () {
    test('rejects invalid ranges and nullable-marker offsets', () {
      final f = SyntaxFixture('T?');
      for (final (start, end) in [(-1, 1), (1, 0), (0, 3)]) {
        expect(
          () => Identifier(source: f.source, start: start, end: end),
          throwsRangeError,
        );
      }
      for (final offset in [-1, 2]) {
        expect(
          () => NamedTypeAnnotation(
            source: f.source,
            start: 0,
            end: 2,
            name: f.id('T'),
            questionOffset: offset,
          ),
          throwsRangeError,
        );
      }
    });

    test('rejects children from another revision of the same URI', () {
      final first = SyntaxFixture('T');
      final second = SyntaxFixture('T');
      expect(first.source.uri, second.source.uri);
      expect(
        () => NamedTypeAnnotation(
          source: first.source,
          start: 0,
          end: 1,
          name: second.id('T'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects out-of-order, overlapping, and escaping children', () {
      final f = SyntaxFixture('1 + 2');
      final first = f.literal('1');
      final last = f.literal('2');
      expect(() => f.binary(last, .add, first), throwsRangeError);
      expect(
        () => BinaryExpression(
          source: f.source,
          start: 0,
          end: 5,
          left: last,
          op: .add,
          right: first,
        ),
        throwsArgumentError,
      );
      expect(
        () => BinaryExpression(
          source: f.source,
          start: 0,
          end: 5,
          left: first,
          op: .add,
          right: first,
        ),
        throwsArgumentError,
      );
      expect(
        () => BinaryExpression(
          source: f.source,
          start: 0,
          end: 4,
          left: first,
          op: .add,
          right: last,
        ),
        throwsArgumentError,
      );
    });

    test(
      'copies child lists and metadata and permits empty recovery ranges',
      () {
        final f = SyntaxFixture('<T>');
        final original = <TypeAnnotation>[f.type('T')];
        final arguments = TypeArgumentList(
          source: f.source,
          start: 0,
          end: 3,
          arguments: original,
        );
        original.clear();
        expect(arguments.arguments.single.text, 'T');
        expect(() => arguments.arguments.clear(), throwsUnsupportedError);
        final empty = SyntaxFixture('');
        final metadata = <Annotation>[];
        final typeParameter = TypeParameter(
          source: empty.source,
          start: 0,
          end: 0,
          metadata: metadata,
          name: Identifier(source: empty.source, start: 0, end: 0),
          bound: MissingTypeAnnotation(source: empty.source, offset: 0),
        );
        metadata.add(
          Annotation(source: empty.source, start: 0, end: 0, name: []),
        );
        expect(typeParameter.metadata, isEmpty);
        expect(() => typeParameter.metadata.clear(), throwsUnsupportedError);
        expect(walk(typeParameter), [
          typeParameter,
          typeParameter.name,
          typeParameter.bound,
        ]);
        checkTree(typeParameter);
      },
    );
  });
}
