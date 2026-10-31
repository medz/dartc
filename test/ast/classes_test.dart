import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

TypeParameterList typeParameters(SyntaxFixture f, {String? bound}) {
  final start = f.at('<');
  final end = f.at('>') + 1;
  return TypeParameterList(
    source: f.source,
    start: start,
    end: end,
    parameters: [
      TypeParameter(
        source: f.source,
        start: start + 1,
        end: end - 1,
        name: f.id('T', start),
        bound: bound == null ? null : f.type(bound),
      ),
    ],
  );
}

NamedTypeAnnotation appliedType(SyntaxFixture f, String name, [int from = 0]) {
  final start = f.at('$name<T>', from);
  return NamedTypeAnnotation(
    source: f.source,
    start: start,
    end: start + name.length + 3,
    name: f.id(name, start),
    typeArguments: TypeArgumentList(
      source: f.source,
      start: start + name.length,
      end: start + name.length + 3,
      arguments: [f.type('T', from: start + name.length)],
    ),
  );
}

void main() {
  group('Class declarations', () {
    test(
      'retains primary headers, clauses, metadata and members in source order',
      () {
        final f = SyntaxFixture(
          '@tag abstract base class const C<T extends num>.named(final T value) extends B<T> with M<T>, N implements I<T> { @member T get data => value; }',
        );
        final metadata = [f.annotation('tag')];
        final modifiers = [
          ClassModifier.abstractKeyword,
          ClassModifier.baseKeyword,
        ];
        final valueType = f.type('T', from: f.at('final T'));
        final parameter = FormalParameter(
          source: f.source,
          start: f.at('final T'),
          end: f.at(')'),
          kind: .requiredPositional,
          keyword: .finalKeyword,
          type: valueType,
          name: f.id('value'),
        );
        final mixinTypes = <TypeAnnotation>[appliedType(f, 'M'), f.type('N')];
        final memberStart = f.at('@member');
        final members = <ClassMember>[
          GetterDeclaration(
            source: f.source,
            start: memberStart,
            end: f.at(';') + 1,
            metadata: [f.annotation('member')],
            returnType: f.type('T', from: memberStart),
            name: f.id('data'),
            body: ExpressionFunctionBody(
              source: f.source,
              start: f.at('=>'),
              end: f.at(';') + 1,
              expression: f.reference('value', f.at('=>')),
            ),
          ),
        ];
        final node = ClassDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: metadata,
          modifiers: modifiers,
          name: f.id('C'),
          typeParameters: typeParameters(f, bound: 'num'),
          isConst: true,
          primaryConstructorName: f.id('named'),
          primaryParameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [parameter],
          ),
          extendsClause: ExtendsClause(
            source: f.source,
            start: f.at('extends B'),
            end: f.at(' with'),
            superclass: appliedType(f, 'B'),
          ),
          withClause: TypeListClause(
            source: f.source,
            start: f.at('with'),
            end: f.at(' implements'),
            kind: .withKeyword,
            types: mixinTypes,
          ),
          implementsClause: TypeListClause(
            source: f.source,
            start: f.at('implements'),
            end: f.at(' {'),
            kind: .implementsKeyword,
            types: [appliedType(f, 'I')],
          ),
          members: members,
        );
        metadata.clear();
        modifiers.clear();
        members.clear();
        mixinTypes.clear();
        checkTree(node);
        expect(
          [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
          [
            '@tag',
            'C',
            '<T extends num>',
            'named',
            '(final T value)',
            'extends B<T>',
            'with M<T>, N',
            'implements I<T>',
            '@member T get data => value;',
          ],
        );
        expect(node.modifiers, [
          ClassModifier.abstractKeyword,
          ClassModifier.baseKeyword,
        ]);
        expect(node.isConst, isTrue);
        expect(
          node.primaryParameters!.parameters.single.keyword,
          VariableKeyword.finalKeyword,
        );
        expect(walk(node).whereType<FieldDeclaration>(), isEmpty);
        expect(walk(node).whereType<ConstructorDeclaration>(), isEmpty);
        expect(() => node.modifiers.clear(), throwsUnsupportedError);
        expect(() => node.metadata.clear(), throwsUnsupportedError);
        expect(() => node.members.clear(), throwsUnsupportedError);
        expect(() => node.withClause!.types.clear(), throwsUnsupportedError);
      },
    );

    test(
      'distinguishes empty braced and semicolon bodies without invented syntax',
      () {
        for (final (text, modifiers, semicolon) in [
          ('class C {}', <ClassModifier>[], false),
          ('sealed class C;', [ClassModifier.sealedKeyword], true),
          (
            'abstract base mixin class C;',
            [
              ClassModifier.abstractKeyword,
              ClassModifier.baseKeyword,
              ClassModifier.mixinKeyword,
            ],
            true,
          ),
          (
            'abstract interface class C;',
            [ClassModifier.abstractKeyword, ClassModifier.interfaceKeyword],
            true,
          ),
          ('final class C;', [ClassModifier.finalKeyword], true),
        ]) {
          final f = SyntaxFixture(text);
          final node = ClassDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('C'),
            modifiers: modifiers,
            isSemicolonBody: semicolon,
          );
          checkTree(node);
          expect(node.childCount, 1);
          expect(node.isSemicolonBody, semicolon);
          expect(node.primaryParameters, isNull);
          expect(node.extendsClause, isNull);
          expect(node.modifiers, modifiers);
        }
      },
    );

    test('keeps an explicit new primary name and an empty parameter list', () {
      final f = SyntaxFixture('class C.new();');
      final node = ClassDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        name: f.id('C'),
        primaryConstructorName: f.id('new'),
        primaryParameters: f.emptyParameters(f.at('()')),
        isSemicolonBody: true,
      );
      checkTree(node);
      expect(node.primaryConstructorName!.text, 'new');
      expect(node.primaryParameters!.parameters, isEmpty);
      expect(node.childCount, 3);
    });

    test('preserves named mixin applications without an extends clause or class body', () {
      final f = SyntaxFixture(
        '@tag abstract class C<T> = B<T> with M<T>, N implements I<T>;',
      );
      final node = ClassTypeAliasDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: [f.annotation('tag')],
        modifiers: [.abstractKeyword],
        name: f.id('C'),
        typeParameters: typeParameters(f),
        superclass: appliedType(f, 'B'),
        withClause: TypeListClause(
          source: f.source,
          start: f.at('with'),
          end: f.at(' implements'),
          kind: .withKeyword,
          types: [appliedType(f, 'M'), f.type('N')],
        ),
        implementsClause: TypeListClause(
          source: f.source,
          start: f.at('implements'),
          end: f.at(';'),
          kind: .implementsKeyword,
          types: [appliedType(f, 'I')],
        ),
      );
      checkTree(node);
      expect(
        [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
        ['@tag', 'C', '<T>', 'B<T>', 'with M<T>, N', 'implements I<T>'],
      );
      expect(() => node.modifiers.clear(), throwsUnsupportedError);
      final g = SyntaxFixture('class C = B with M;');
      final short = ClassTypeAliasDeclaration(
        source: g.source,
        start: 0,
        end: g.source.length,
        name: g.id('C'),
        superclass: g.type('B'),
        withClause: TypeListClause(
          source: g.source,
          start: g.at('with'),
          end: g.at(';'),
          kind: .withKeyword,
          types: [g.type('M')],
        ),
      );
      checkTree(short);
      expect(short.childCount, 3);
    });

    test('represents base mixin constraints and members, and empty mixins', () {
      final f = SyntaxFixture(
        '@tag base mixin M<T> on B<T>, C implements I<T> { T get value; }',
      );
      final member = GetterDeclaration(
        source: f.source,
        start: f.at('T get'),
        end: f.at(';') + 1,
        returnType: f.type('T', from: f.at('T get')),
        name: f.id('value'),
        body: EmptyFunctionBody(
          source: f.source,
          start: f.at(';'),
          end: f.at(';') + 1,
        ),
      );
      final members = <ClassMember>[member];
      final node = MixinDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: [f.annotation('tag')],
        isBase: true,
        name: f.id('M'),
        typeParameters: typeParameters(f),
        onClause: TypeListClause(
          source: f.source,
          start: f.at('on'),
          end: f.at(' implements'),
          kind: .onKeyword,
          types: [appliedType(f, 'B'), f.type('C')],
        ),
        implementsClause: TypeListClause(
          source: f.source,
          start: f.at('implements'),
          end: f.at(' {'),
          kind: .implementsKeyword,
          types: [appliedType(f, 'I')],
        ),
        members: members,
      );
      members.clear();
      checkTree(node);
      expect(node.isBase, isTrue);
      expect(node.members.single, same(member));
      expect(node.onClause!.types.map((t) => t.text), ['B<T>', 'C']);
      expect(() => node.members.clear(), throwsUnsupportedError);
      final g = SyntaxFixture('mixin M;');
      final empty = MixinDeclaration(
        source: g.source,
        start: 0,
        end: g.source.length,
        name: g.id('M'),
        isSemicolonBody: true,
      );
      checkTree(empty);
      expect(empty.childCount, 1);
    });

    test(
      'rejects stale members, overlapping headers, and reversed type lists',
      () {
        final f = SyntaxFixture('class C extends B { int get x; }');
        final old = SyntaxFixture(f.source.text);
        final stale = GetterDeclaration(
          source: old.source,
          start: old.at('int'),
          end: old.at(';') + 1,
          name: old.id('x', old.at('get')),
          body: EmptyFunctionBody(
            source: old.source,
            start: old.at(';'),
            end: old.at(';') + 1,
          ),
        );
        expect(
          () => ClassDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('C'),
            members: [stale],
          ),
          throwsArgumentError,
        );
        expect(
          () => ClassDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('C'),
            extendsClause: ExtendsClause(
              source: f.source,
              start: 0,
              end: f.at(' {'),
              superclass: f.type('B'),
            ),
          ),
          throwsArgumentError,
        );
        final g = SyntaxFixture('on A, B');
        expect(
          () => TypeListClause(
            source: g.source,
            start: 0,
            end: g.source.length,
            kind: .onKeyword,
            types: [g.type('B'), g.type('A')],
          ),
          throwsArgumentError,
        );
        expect(
          () => ClassTypeAliasDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('C'),
            superclass: old.type('B'),
            withClause: TypeListClause(
              source: f.source,
              start: f.at('B'),
              end: f.at('B') + 1,
              kind: .withKeyword,
              types: [],
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => MixinDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('C'),
            members: [stale],
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
