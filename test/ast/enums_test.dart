import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Enum declarations', () {
    test('retains constants without adding implicit members', () {
      final f = SyntaxFixture('@tag enum Color { red, green, blue, }');
      final metadata = [f.annotation('tag')];
      final constants = [
        for (final name in ['red', 'green', 'blue'])
          EnumConstantDeclaration(
            source: f.source,
            start: f.at(name),
            end: f.at(name) + name.length,
            name: f.id(name),
          ),
      ];
      final node = EnumDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        name: f.id('Color'),
        constants: constants,
      );
      metadata.clear();
      constants.clear();
      checkTree(CompilationUnit(source: f.source, members: [node]));
      expect(_children(node), ['@tag', 'Color', 'red', 'green', 'blue']);
      expect(node.primaryParameters, isNull);
      expect(node.members, isEmpty);
      expect(node.isConst, isFalse);
      expect(node.hasMemberSeparator, isFalse);
      expect(node.constants.every((c) => c.arguments == null), isTrue);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      expect(() => node.constants.clear(), throwsUnsupportedError);
      expect(() => node.members.clear(), throwsUnsupportedError);
    });

    test('preserves annotated generic constants and named arguments', () {
      final f = SyntaxFixture("@tag first<int>.named(1, label: 'a')");
      final metadata = [f.annotation('tag')];
      final argumentValues = [
        Argument(
          source: f.source,
          start: f.at('1'),
          end: f.at('1') + 1,
          value: f.literal('1'),
        ),
        Argument(
          source: f.source,
          start: f.at('label'),
          end: f.at(')'),
          name: f.id('label'),
          value: f.string("'a'"),
        ),
      ];
      final arguments = ArgumentList(
        source: f.source,
        start: f.at('('),
        end: f.source.length,
        arguments: argumentValues,
      );
      final node = EnumConstantDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        name: f.id('first'),
        typeArguments: _typeArguments(f),
        constructorName: f.id('named'),
        arguments: arguments,
      );
      metadata.clear();
      argumentValues.clear();
      checkTree(node);
      expect(_children(node), [
        '@tag',
        'first',
        '<int>',
        'named',
        "(1, label: 'a')",
      ]);
      expect(node.arguments, same(arguments));
      expect(_children(arguments), ['1', "label: 'a'"]);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      expect(() => arguments.arguments.clear(), throwsUnsupportedError);
    });

    test('distinguishes omitted arguments, empty calls, and explicit new', () {
      for (final (text, suffix) in [
        ('entry', null),
        ('entry()', null),
        ('entry.named()', 'named'),
        ('entry<int>.new()', 'new'),
      ]) {
        final f = SyntaxFixture(text);
        final node = EnumConstantDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('entry'),
          typeArguments: text.contains('<') ? _typeArguments(f) : null,
          constructorName: suffix == null ? null : f.id(suffix),
          arguments: text.endsWith('()')
              ? ArgumentList(
                  source: f.source,
                  start: f.at('('),
                  end: f.source.length,
                  arguments: [],
                )
              : null,
        );
        checkTree(node);
        expect(node.arguments == null, text == 'entry');
        expect(node.arguments?.arguments, text == 'entry' ? null : isEmpty);
        expect(node.constructorName?.text, suffix);
      }
    });

    test(
      'retains primary headers and member bodies at their written positions',
      () {
        final f = SyntaxFixture(
          '@tag enum const E<T>.named(final T value) with M implements I { a<int>.named(1); this : assert(ready); }',
        );
        final constantStart = f.at('a<int>');
        final constantEnd = f.at(';');
        final members = <ClassMember>[
          PrimaryConstructorBody(
            source: f.source,
            start: f.at('this'),
            end: f.at(';', constantEnd + 1) + 1,
            initializers: [
              AssertInitializer(
                source: f.source,
                start: f.at('assert'),
                end: f.at(')', f.at('assert')) + 1,
                condition: f.reference('ready'),
              ),
            ],
            body: EmptyFunctionBody(
              source: f.source,
              start: f.at(';', constantEnd + 1),
              end: f.at(';', constantEnd + 1) + 1,
            ),
          ),
        ];
        final node = EnumDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: [f.annotation('tag')],
          name: f.id('E'),
          isConst: true,
          typeParameters: TypeParameterList(
            source: f.source,
            start: f.at('<T>'),
            end: f.at('<T>') + 3,
            parameters: [
              TypeParameter(
                source: f.source,
                start: f.at('T'),
                end: f.at('T') + 1,
                name: f.id('T'),
              ),
            ],
          ),
          primaryConstructorName: f.id('named'),
          primaryParameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [
              FormalParameter(
                source: f.source,
                start: f.at('final'),
                end: f.at(')'),
                kind: .requiredPositional,
                keyword: .finalKeyword,
                type: f.type('T', from: f.at('final')),
                name: f.id('value'),
              ),
            ],
          ),
          withClause: TypeListClause(
            source: f.source,
            start: f.at('with'),
            end: f.at(' implements'),
            kind: .withKeyword,
            types: [f.type('M')],
          ),
          implementsClause: TypeListClause(
            source: f.source,
            start: f.at('implements'),
            end: f.at(' {'),
            kind: .implementsKeyword,
            types: [f.type('I')],
          ),
          hasMemberSeparator: true,
          constants: [
            EnumConstantDeclaration(
              source: f.source,
              start: constantStart,
              end: constantEnd,
              name: f.id('a', constantStart),
              typeArguments: _typeArguments(f),
              constructorName: f.id('named', constantStart),
              arguments: ArgumentList(
                source: f.source,
                start: f.at('(1)'),
                end: constantEnd,
                arguments: [
                  Argument(
                    source: f.source,
                    start: f.at('1'),
                    end: f.at('1') + 1,
                    value: f.literal('1'),
                  ),
                ],
              ),
            ),
          ],
          members: members,
        );
        members.clear();
        checkTree(node);
        expect(_children(node), [
          '@tag',
          'E',
          '<T>',
          'named',
          '(final T value)',
          'with M',
          'implements I',
          'a<int>.named(1)',
          'this : assert(ready);',
        ]);
        expect(node.isConst, isTrue);
        expect(node.hasMemberSeparator, isTrue);
        expect(node.members.single, isA<PrimaryConstructorBody>());
        expect(walk(node).whereType<FieldDeclaration>(), isEmpty);
        expect(walk(node).whereType<InstanceCreationExpression>(), isEmpty);
        expect(() => node.members.clear(), throwsUnsupportedError);
      },
    );

    test('retains empty bodies and the member separator', () {
      for (final text in ['enum E {}', 'enum E {;}', 'enum E;']) {
        final f = SyntaxFixture(text);
        final node = EnumDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('E'),
          isSemicolonBody: text.endsWith(';'),
          hasMemberSeparator: text.contains('{;}'),
        );
        checkTree(node);
        expect(_children(node), ['E']);
        expect(node.constants, isEmpty);
        expect(node.members, isEmpty);
        expect(node.isSemicolonBody, text == 'enum E;');
        expect(node.hasMemberSeparator, text == 'enum E {;}');
      }
    });

    test(
      'rejects stale, reversed, and out-of-range constants or call children',
      () {
        const text = 'enum E { a, b }';
        final f = SyntaxFixture(text);
        final stale = SyntaxFixture(text);
        EnumConstantDeclaration entry(SyntaxFixture f, String name) =>
            EnumConstantDeclaration(
              source: f.source,
              start: f.at(name, f.at('{')),
              end: f.at(name, f.at('{')) + 1,
              name: f.id(name, f.at('{')),
            );
        for (final constants in [
          [entry(stale, 'a')],
          [entry(f, 'b'), entry(f, 'a')],
        ]) {
          expect(
            () => EnumDeclaration(
              source: f.source,
              start: 0,
              end: f.source.length,
              name: f.id('E'),
              constants: constants,
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => EnumConstantDeclaration(
            source: f.source,
            start: f.at('a'),
            end: f.at('a') + 1,
            name: f.id('b'),
          ),
          throwsArgumentError,
        );
        final call = SyntaxFixture('entry<int>.named()');
        final old = SyntaxFixture(call.source.text);
        expect(
          () => EnumConstantDeclaration(
            source: call.source,
            start: 0,
            end: call.source.length,
            name: call.id('entry'),
            typeArguments: _typeArguments(old),
          ),
          throwsArgumentError,
        );
        expect(
          () => EnumConstantDeclaration(
            source: call.source,
            start: 0,
            end: call.source.length,
            name: call.id('named'),
            typeArguments: _typeArguments(call),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

List<String> _children(AstNode node) => [
  for (var i = 0; i < node.childCount; i++) node.childAt(i).text,
];

TypeArgumentList _typeArguments(SyntaxFixture f) => TypeArgumentList(
  source: f.source,
  start: f.at('<int>'),
  end: f.at('<int>') + 5,
  arguments: [f.type('int')],
);
