import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Type alias syntax', () {
    test(
      'retains modern generic aliases without expanding the written type',
      () {
        final f = SyntaxFixture(
          '@tag typedef Items<T extends num> = List<T?>;',
        );
        final parameterStart = f.at('<');
        final metadata = [f.annotation('tag')];
        final rhs = NamedTypeAnnotation(
          source: f.source,
          start: f.at('List'),
          end: f.at(';'),
          name: f.id('List'),
          typeArguments: TypeArgumentList(
            source: f.source,
            start: f.at('<', f.at('=')),
            end: f.at(';'),
            arguments: [f.type('T', from: f.at('='), nullable: true)],
          ),
        );
        final node = TypeAliasDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: metadata,
          name: f.id('Items'),
          typeParameters: TypeParameterList(
            source: f.source,
            start: parameterStart,
            end: f.at('>') + 1,
            parameters: [
              TypeParameter(
                source: f.source,
                start: parameterStart + 1,
                end: f.at('>'),
                name: f.id('T', parameterStart),
                bound: f.type('num'),
              ),
            ],
          ),
          type: rhs,
        );
        metadata.clear();
        checkTree(node);
        expect(node.type, same(rhs));
        expect(rhs.text, 'List<T?>');
        expect(
          [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
          ['@tag', 'Items', '<T extends num>', 'List<T?>'],
        );
        expect(() => node.metadata.clear(), throwsUnsupportedError);
      },
    );

    test(
      'keeps a generic function type distinct from alias type parameters',
      () {
        final f = SyntaxFixture('typedef Callback = int Function<T>(T value);');
        final innerTypeParameters = TypeParameterList(
          source: f.source,
          start: f.at('<'),
          end: f.at('>') + 1,
          parameters: [
            TypeParameter(
              source: f.source,
              start: f.at('<') + 1,
              end: f.at('>'),
              name: f.id('T'),
            ),
          ],
        );
        final function = FunctionTypeAnnotation(
          source: f.source,
          start: f.at('int'),
          end: f.at(';'),
          returnType: f.type('int'),
          typeParameters: innerTypeParameters,
          parameters: FunctionTypeParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [
              FunctionTypeParameter(
                source: f.source,
                start: f.at('(') + 1,
                end: f.at(')'),
                kind: .requiredPositional,
                type: f.type('T', from: f.at('(')),
                name: f.id('value'),
              ),
            ],
          ),
        );
        final node = TypeAliasDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('Callback'),
          type: function,
        );
        checkTree(node);
        expect(node.typeParameters, isNull);
        expect(function.typeParameters, same(innerTypeParameters));
        expect(node.childCount, 2);
      },
    );

    test(
      'retains legacy function alias spelling, generics, and named parameters',
      () {
        final f = SyntaxFixture(
          '@tag typedef int Callback<T>(T value, {required int count});',
        );
        final node = FunctionTypeAliasDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: [f.annotation('tag')],
          returnType: f.type('int'),
          name: f.id('Callback'),
          typeParameters: TypeParameterList(
            source: f.source,
            start: f.at('<'),
            end: f.at('>') + 1,
            parameters: [
              TypeParameter(
                source: f.source,
                start: f.at('<') + 1,
                end: f.at('>'),
                name: f.id('T'),
              ),
            ],
          ),
          parameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [
              f.parameter('value', type: f.type('T', from: f.at('('))),
              FormalParameter(
                source: f.source,
                start: f.at('required'),
                end: f.at('}'),
                kind: .requiredNamed,
                type: f.type('int', from: f.at('required')),
                name: f.id('count'),
              ),
            ],
          ),
        );
        checkTree(node);
        expect(
          [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
          ['@tag', 'int', 'Callback', '<T>', '(T value, {required int count})'],
        );
        expect(
          node.parameters.parameters.last.kind,
          FormalParameterKind.requiredNamed,
        );
        expect(walk(node).whereType<FunctionTypeAnnotation>(), isEmpty);
      },
    );

    test('keeps omitted types in legacy aliases absent', () {
      final f = SyntaxFixture('typedef Untyped(value, [fallback]);');
      final node = FunctionTypeAliasDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        name: f.id('Untyped'),
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [
            f.parameter('value'),
            f.parameter('fallback', kind: .optionalPositional),
          ],
        ),
      );
      checkTree(node);
      expect(node.returnType, isNull);
      expect(node.typeParameters, isNull);
      expect(node.parameters.parameters.every((p) => p.type == null), isTrue);
      expect(node.childCount, 2);
    });

    test('rejects stale types and reversed alias components', () {
      final f = SyntaxFixture('typedef A = B;');
      final old = SyntaxFixture(f.source.text);
      expect(
        () => TypeAliasDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('A'),
          type: old.type('B'),
        ),
        throwsArgumentError,
      );
      expect(
        () => TypeAliasDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('B'),
          type: f.type('A'),
        ),
        throwsArgumentError,
      );
    });
  });
}
