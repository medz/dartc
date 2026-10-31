import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Top-level declarations', () {
    test(
      'functions retain metadata, return type, generics, parameters, and body',
      () {
        final f = SyntaxFixture(
          '@tag T identity<T extends num>(T value) => value;',
        );
        final metadata = [f.annotation('tag')];
        final typeParameters = TypeParameterList(
          source: f.source,
          start: f.at('<'),
          end: f.at('>') + 1,
          parameters: [
            TypeParameter(
              source: f.source,
              start: f.at('<') + 1,
              end: f.at('>'),
              name: f.id('T', f.at('<')),
              bound: f.type('num'),
            ),
          ],
        );
        final parameters = FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [
            f.parameter('value', type: f.type('T', from: f.at('('))),
          ],
        );
        final body = ExpressionFunctionBody(
          source: f.source,
          start: f.at('=>'),
          end: f.source.length,
          expression: f.reference('value', f.at('=>')),
        );
        final node = TopLevelFunctionDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: metadata,
          returnType: f.type('T'),
          name: f.id('identity'),
          typeParameters: typeParameters,
          parameters: parameters,
          body: body,
        );
        metadata.clear();
        checkTree(node);
        expect(
          [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
          [
            '@tag',
            'T',
            'identity',
            '<T extends num>',
            '(T value)',
            '=> value;',
          ],
        );
        expect(node.isExternal, isFalse);
        expect(() => node.metadata.clear(), throwsUnsupportedError);
      },
    );

    test(
      'keeps omitted annotations and external semicolon bodies explicit',
      () {
        final f = SyntaxFixture('start() {} external void stop();');
        final start = TopLevelFunctionDeclaration(
          source: f.source,
          start: 0,
          end: f.at(' external'),
          name: f.id('start'),
          parameters: f.emptyParameters(5),
          body: f.emptyBlock(8),
        );
        final stop = TopLevelFunctionDeclaration(
          source: f.source,
          start: f.at('external'),
          end: f.source.length,
          isExternal: true,
          returnType: f.type('void'),
          name: f.id('stop'),
          parameters: f.emptyParameters(f.at('stop') + 4),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';'),
            end: f.source.length,
          ),
        );
        checkTree(start);
        checkTree(stop);
        expect(start.returnType, isNull);
        expect(start.typeParameters, isNull);
        expect(start.childCount, 3);
        expect(stop.isExternal, isTrue);
        expect(stop.body, isA<EmptyFunctionBody>());
      },
    );

    test('getter and setter declarations retain their distinct signatures', () {
      final f = SyntaxFixture(
        '@tag int get answer => 42; set answer(int value) {}',
      );
      final getterMetadata = [f.annotation('tag')];
      final getter = TopLevelGetterDeclaration(
        source: f.source,
        start: 0,
        end: f.at(';') + 1,
        metadata: getterMetadata,
        returnType: f.type('int'),
        name: f.id('answer'),
        body: ExpressionFunctionBody(
          source: f.source,
          start: f.at('=>'),
          end: f.at(';') + 1,
          expression: f.literal('42'),
        ),
      );
      final setter = TopLevelSetterDeclaration(
        source: f.source,
        start: f.at('set'),
        end: f.source.length,
        name: f.id('answer', f.at('set')),
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [
            f.parameter('value', type: f.type('int', from: f.at('('))),
          ],
        ),
        body: f.emptyBlock(f.at('{')),
      );
      getterMetadata.clear();
      checkTree(getter);
      checkTree(setter);
      expect(getter.metadata.single.text, '@tag');
      expect(walk(getter).whereType<FormalParameterList>(), isEmpty);
      expect(setter.returnType, isNull);
      expect(setter.parameters.parameters.single.name.text, 'value');
      expect(walk(getter).whereType<Identifier>().map((n) => n.text), [
        'tag',
        'int',
        'answer',
      ]);
    });

    test(
      'external accessors retain metadata and an optional written return type',
      () {
        final f = SyntaxFixture(
          '@tag external get value; @tag external void set value(v);',
        );
        final getter = TopLevelGetterDeclaration(
          source: f.source,
          start: 0,
          end: f.at(';') + 1,
          metadata: [f.annotation('tag')],
          isExternal: true,
          name: f.id('value'),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';'),
            end: f.at(';') + 1,
          ),
        );
        final secondStart = f.at('@tag', 1);
        final secondMetadata = [
          Annotation(
            source: f.source,
            start: secondStart,
            end: secondStart + 4,
            name: [f.id('tag', secondStart)],
          ),
        ];
        final setter = TopLevelSetterDeclaration(
          source: f.source,
          start: secondStart,
          end: f.source.length,
          metadata: secondMetadata,
          isExternal: true,
          returnType: f.type('void'),
          name: f.id('value', secondStart),
          parameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [f.parameter('v', from: f.at('('))],
          ),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.source.length - 1,
            end: f.source.length,
          ),
        );
        secondMetadata.clear();
        checkTree(getter);
        checkTree(setter);
        expect(getter.returnType, isNull);
        expect(getter.isExternal, isTrue);
        expect(setter.isExternal, isTrue);
        expect(setter.returnType!.text, 'void');
        expect(setter.metadata.single.start, secondStart);
        expect(() => setter.metadata.clear(), throwsUnsupportedError);
      },
    );

    test(
      'variable lists own metadata once and retain multiple initializers',
      () {
        final f = SyntaxFixture(
          '@tag late final int a = first(), b = second();',
        );
        final metadata = [f.annotation('tag')];
        final declarations = [
          for (final (name, function) in [('a', 'first'), ('b', 'second')])
            VariableDeclaration(
              source: f.source,
              start: f.at(name, f.at('int') + 3),
              end: f.at(function) + function.length + 2,
              name: f.id(name, f.at('int') + 3),
              initializer: f.emptyCall(function),
            ),
        ];
        final variables = VariableDeclarationList(
          source: f.source,
          start: 0,
          end: f.source.length - 1,
          metadata: metadata,
          keyword: .finalKeyword,
          isLate: true,
          type: f.type('int'),
          declarations: declarations,
        );
        final node = TopLevelVariableDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          variables: variables,
        );
        metadata.clear();
        declarations.clear();
        checkTree(node);
        expect(node.childAt(0), same(variables));
        expect(walk(node).whereType<Annotation>().length, 1);
        expect(
          walk(node).whereType<InvocationExpression>().map((n) => n.text),
          ['first()', 'second()'],
        );
        expect(variables.isLate, isTrue);
        expect(variables.keyword, VariableKeyword.finalKeyword);
        expect(variables.text.endsWith(';'), isFalse);
        final g = SyntaxFixture('@tag external int value;');
        final external = TopLevelVariableDeclaration(
          source: g.source,
          start: 0,
          end: g.source.length,
          isExternal: true,
          variables: VariableDeclarationList(
            source: g.source,
            start: 0,
            end: g.source.length - 1,
            metadata: [g.annotation('tag')],
            type: g.type('int'),
            declarations: [
              VariableDeclaration(
                source: g.source,
                start: g.at('value'),
                end: g.at(';'),
                name: g.id('value'),
              ),
            ],
          ),
        );
        checkTree(external);
        expect(external.isExternal, isTrue);
        expect(external.variables.declarations.single.initializer, isNull);
      },
    );

    test(
      'rejects stale bodies, reversed signature fields, and out-of-range lists',
      () {
        final f = SyntaxFixture('void f() {}');
        final old = SyntaxFixture(f.source.text);
        expect(
          () => TopLevelFunctionDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            returnType: f.type('void'),
            name: f.id('f'),
            parameters: f.emptyParameters(6),
            body: old.emptyBlock(9),
          ),
          throwsArgumentError,
        );
        expect(
          () => TopLevelGetterDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('f'),
            returnType: f.type('f'),
            body: f.emptyBlock(9),
          ),
          throwsArgumentError,
        );
        expect(
          () => TopLevelSetterDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: Identifier(source: f.source, start: 9, end: 10),
            parameters: f.emptyParameters(6),
            body: f.emptyBlock(9),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
