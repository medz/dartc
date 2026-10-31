import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Class members', () {
    test('shares field metadata once and preserves initializer order', () {
      final f = SyntaxFixture(
        '@tag static late final int a = first(), b = second();',
      );
      final metadata = [f.annotation('tag')];
      final variables = <VariableDeclaration>[
        for (final (name, value) in [('a', 'first'), ('b', 'second')])
          VariableDeclaration(
            source: f.source,
            start: f.at(name, f.at('int') + 3),
            end: f.at(value) + value.length + 2,
            name: f.id(name, f.at('int') + 3),
            initializer: f.emptyCall(value),
          ),
      ];
      final node = FieldDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        isStatic: true,
        variables: VariableDeclarationList(
          source: f.source,
          start: 0,
          end: f.source.length - 1,
          metadata: metadata,
          isLate: true,
          keyword: .finalKeyword,
          type: f.type('int'),
          declarations: variables,
        ),
      );
      metadata.clear();
      variables.clear();
      checkTree(node);
      expect(node.isStatic, isTrue);
      expect(node.variables.isLate, isTrue);
      expect(node.variables.keyword, VariableKeyword.finalKeyword);
      expect(walk(node).whereType<Annotation>().length, 1);
      expect(walk(node).whereType<InvocationExpression>().map((v) => v.text), [
        'first()',
        'second()',
      ]);
      expect(node.variables.text.endsWith(';'), isFalse);
      expect(() => node.variables.declarations.clear(), throwsUnsupportedError);
    });

    test('retains abstract, covariant and external fields without adding accessors', () {
      for (final external in [false, true]) {
        final f = SyntaxFixture(
          external ? 'external int value;' : 'abstract covariant num value;',
        );
        final node = FieldDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          isExternal: external,
          isAbstract: !external,
          isCovariant: !external,
          variables: VariableDeclarationList(
            source: f.source,
            start: 0,
            end: f.at(';'),
            type: f.type(external ? 'int' : 'num'),
            declarations: [
              VariableDeclaration(
                source: f.source,
                start: f.at('value'),
                end: f.at(';'),
                name: f.id('value'),
              ),
            ],
          ),
        );
        checkTree(node);
        expect(node.isExternal, external);
        expect(node.isAbstract, !external);
        expect(node.isCovariant, !external);
        expect(walk(node).whereType<GetterDeclaration>(), isEmpty);
        expect(node.variables.declarations.single.initializer, isNull);
      }
    });

    test('keeps generic method signatures and external/static flags', () {
      final f = SyntaxFixture('@tag external static T convert<T>(T value);');
      final metadata = [f.annotation('tag')];
      final t = f.at('<T>');
      final parameter = f.parameter(
        'value',
        type: f.type('T', from: f.at('(')),
      );
      final node = MethodDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        isExternal: true,
        isStatic: true,
        returnType: f.type('T'),
        name: f.id('convert'),
        typeParameters: TypeParameterList(
          source: f.source,
          start: t,
          end: t + 3,
          parameters: [
            TypeParameter(
              source: f.source,
              start: t + 1,
              end: t + 2,
              name: f.id('T', t),
            ),
          ],
        ),
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [parameter],
        ),
        body: EmptyFunctionBody(
          source: f.source,
          start: f.at(';'),
          end: f.source.length,
        ),
      );
      metadata.clear();
      checkTree(node);
      expect(
        [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
        ['@tag', 'T', 'convert', '<T>', '(T value)', ';'],
      );
      expect(node.isStatic && node.isExternal, isTrue);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      final g = SyntaxFixture('run() {}');
      final plain = MethodDeclaration(
        source: g.source,
        start: 0,
        end: g.source.length,
        name: g.id('run'),
        parameters: g.emptyParameters(g.at('()')),
        body: g.emptyBlock(g.at('{}')),
      );
      checkTree(plain);
      expect(plain.returnType, isNull);
      expect(plain.typeParameters, isNull);
      expect(plain.childCount, 3);
    });

    test('keeps getter and setter signatures separate', () {
      final f = SyntaxFixture(
        '@tag static int get value => 1; external set value(int next);',
      );
      final getter = GetterDeclaration(
        source: f.source,
        start: 0,
        end: f.at(';') + 1,
        metadata: [f.annotation('tag')],
        isStatic: true,
        returnType: f.type('int'),
        name: f.id('value'),
        body: ExpressionFunctionBody(
          source: f.source,
          start: f.at('=>'),
          end: f.at(';') + 1,
          expression: f.literal('1'),
        ),
      );
      final from = f.at('external');
      final setter = SetterDeclaration(
        source: f.source,
        start: from,
        end: f.source.length,
        isExternal: true,
        name: f.id('value', from),
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [f.parameter('next', type: f.type('int', from: from))],
        ),
        body: EmptyFunctionBody(
          source: f.source,
          start: f.source.length - 1,
          end: f.source.length,
        ),
      );
      checkTree(getter);
      checkTree(setter);
      expect(getter.isStatic, isTrue);
      expect(walk(getter).whereType<FormalParameterList>(), isEmpty);
      expect(setter.isExternal, isTrue);
      expect(setter.returnType, isNull);
      expect(setter.parameters.parameters.single.name.text, 'next');
      expect(() => getter.metadata.clear(), throwsUnsupportedError);
    });

    test('preserves all declared operators and distinguishes minus by its parameters', () {
      final cases = <(DeclaredOperator, String, int)>[
        (.add, '+', 1),
        (.subtract, '-', 1),
        (.subtract, '-', 0),
        (.multiply, '*', 1),
        (.divide, '/', 1),
        (.truncateDivide, '~/', 1),
        (.remainder, '%', 1),
        (.lessThan, '<', 1),
        (.lessThanOrEqual, '<=', 1),
        (.greaterThan, '>', 1),
        (.greaterThanOrEqual, '>=', 1),
        (.equal, '==', 1),
        (.shiftLeft, '<<', 1),
        (.shiftRight, '>>', 1),
        (.unsignedShiftRight, '>>>', 1),
        (.bitwiseAnd, '&', 1),
        (.bitwiseOr, '|', 1),
        (.bitwiseXor, '^', 1),
        (.bitwiseNot, '~', 0),
        (.indexRead, '[]', 1),
        (.indexAssign, '[]=', 2),
      ];
      for (final (op, spelling, arity) in cases) {
        final params = ['int index', 'int value'].take(arity).join(', ');
        final resultType = switch (op) {
          .indexAssign => 'void',
          .equal => 'bool',
          _ => 'int',
        };
        final f = SyntaxFixture(
          '@tag external $resultType operator $spelling($params);',
        );
        final node = OperatorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: [f.annotation('tag')],
          isExternal: true,
          returnType: f.type(resultType),
          op: op,
          parameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [
              for (final name in ['index', 'value'].take(arity))
                f.parameter(
                  name,
                  type: f.type('int', from: f.at('int $name', f.at('('))),
                ),
            ],
          ),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';'),
            end: f.source.length,
          ),
        );
        checkTree(node);
        expect(node.op.spelling, spelling);
        expect(node.parameters.parameters.length, arity);
        expect(node.isExternal, isTrue);
      }
    });

    test('rejects stale bodies, reversed parameters and fields outside a declaration', () {
      final f = SyntaxFixture('int run() {}');
      final old = SyntaxFixture(f.source.text);
      expect(
        () => MethodDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('run'),
          parameters: f.emptyParameters(f.at('()')),
          body: old.emptyBlock(old.at('{}')),
        ),
        throwsArgumentError,
      );
      expect(
        () => SetterDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('run'),
          parameters: f.emptyParameters(f.at('()')),
          body: EmptyFunctionBody(source: f.source, start: 0, end: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => GetterDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('run'),
          body: old.emptyBlock(old.at('{}')),
        ),
        throwsArgumentError,
      );
      expect(
        () => OperatorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          op: .subtract,
          parameters: f.emptyParameters(f.at('()')),
          body: old.emptyBlock(old.at('{}')),
        ),
        throwsArgumentError,
      );
      final variables = VariableDeclarationList(
        source: f.source,
        start: 0,
        end: 3,
        declarations: [
          VariableDeclaration(
            source: f.source,
            start: 0,
            end: 3,
            name: f.id('int'),
          ),
        ],
      );
      expect(
        () => FieldDeclaration(
          source: f.source,
          start: 4,
          end: f.source.length,
          variables: variables,
        ),
        throwsArgumentError,
      );
    });
  });
}
