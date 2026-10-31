import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Function syntax', () {
    test(
      'retains a generic anonymous arrow without a declaration semicolon',
      () {
        final f = SyntaxFixture('<T extends num>(T value) => value');
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
        final expression = FunctionExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          typeParameters: TypeParameterList(
            source: f.source,
            start: 0,
            end: f.at('>') + 1,
            parameters: [
              TypeParameter(
                source: f.source,
                start: 1,
                end: f.at('>'),
                name: f.id('T'),
                bound: f.type('num'),
              ),
            ],
          ),
          parameters: parameters,
          body: body,
        );
        checkTree(expression);
        expect(expression.childAt(1), same(parameters));
        expect(expression.childAt(2), same(body));
        expect(body.text, '=> value');
        expect(walk(expression).whereType<Identifier>().map((n) => n.text), [
          'T',
          'num',
          'T',
          'value',
          'value',
        ]);
      },
    );

    test('keeps block bodies and all written async or generator modifiers', () {
      for (final (text, modifier) in <(String, FunctionBodyModifier?)>[
        ('() {}', null),
        ('() async {}', .asyncKeyword),
        ('() sync* {}', .syncStar),
        ('() async* {}', .asyncStar),
      ]) {
        final f = SyntaxFixture(text);
        final block = f.emptyBlock(f.at('{'));
        final FunctionBody body = modifier == null
            ? block
            : ModifiedBlockFunctionBody(
                source: f.source,
                start: 3,
                end: f.source.length,
                modifier: modifier,
                block: block,
              );
        final expression = FunctionExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: f.emptyParameters(0),
          body: body,
        );
        checkTree(expression);
        expect(
          walk(expression).whereType<BlockStatement>().single,
          same(block),
        );
        if (modifier == null) {
          expect(expression.body, same(block));
          expect(expression.childCount, 2);
        } else {
          expect((body as ModifiedBlockFunctionBody).modifier, modifier);
          expect(body.childAt(0), same(block));
        }
      }
    });

    test('local declarations retain metadata, return types, and generic scope syntax', () {
      final f = SyntaxFixture('@tag T identity<T>(T value) => value;');
      final metadata = [f.annotation('tag')];
      final body = ExpressionFunctionBody(
        source: f.source,
        start: f.at('=>'),
        end: f.source.length,
        expression: f.reference('value', f.at('=>')),
      );
      final declaration = LocalFunctionDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        returnType: f.type('T'),
        name: f.id('identity'),
        typeParameters: TypeParameterList(
          source: f.source,
          start: f.at('<'),
          end: f.at('>') + 1,
          parameters: [
            TypeParameter(
              source: f.source,
              start: f.at('T', f.at('<')),
              end: f.at('>'),
              name: f.id('T', f.at('<')),
            ),
          ],
        ),
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [
            f.parameter('value', type: f.type('T', from: f.at('('))),
          ],
        ),
        body: body,
      );
      metadata.clear();
      checkTree(declaration);
      expect(declaration.metadata.single.text, '@tag');
      expect(() => declaration.metadata.clear(), throwsUnsupportedError);
      expect(body.text, '=> value;');
      expect(
        [
          for (var i = 0; i < declaration.childCount; i++)
            declaration.childAt(i).text,
        ],
        ['@tag', 'T', 'identity', '<T>', '(T value)', '=> value;'],
      );
    });

    test('local functions can omit both type lists and return annotations', () {
      final f = SyntaxFixture('f() {}');
      final node = LocalFunctionDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        name: f.id('f'),
        parameters: f.emptyParameters(1),
        body: f.emptyBlock(4),
      );
      checkTree(node);
      expect(node.returnType, isNull);
      expect(node.typeParameters, isNull);
      expect(node.childCount, 3);
    });

    test('distinguishes async arrows, semicolon bodies, and empty blocks', () {
      final f = SyntaxFixture('async => value; {}');
      final body = ExpressionFunctionBody(
        source: f.source,
        start: 0,
        end: f.at(';') + 1,
        isAsync: true,
        expression: f.reference('value'),
      );
      final empty = EmptyFunctionBody(
        source: f.source,
        start: f.at(';'),
        end: f.at(';') + 1,
      );
      checkTree(body);
      checkTree(empty);
      expect(body.isAsync, isTrue);
      expect(empty.text, ';');
      expect(empty.childCount, 0);
      expect(f.emptyBlock(f.at('{')).text, '{}');
    });

    test(
      'rejects stale bodies, reversed signature children, and escaping ranges',
      () {
        final f = SyntaxFixture('f() {}');
        final old = SyntaxFixture('f() {}');
        expect(
          () => FunctionExpression(
            source: f.source,
            start: 1,
            end: f.source.length,
            parameters: f.emptyParameters(1),
            body: old.emptyBlock(4),
          ),
          throwsArgumentError,
        );
        expect(
          () => LocalFunctionDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: Identifier(source: f.source, start: 4, end: 5),
            parameters: f.emptyParameters(1),
            body: f.emptyBlock(4),
          ),
          throwsArgumentError,
        );
        expect(
          () => ModifiedBlockFunctionBody(
            source: f.source,
            start: 0,
            end: 5,
            modifier: .asyncKeyword,
            block: f.emptyBlock(4),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
