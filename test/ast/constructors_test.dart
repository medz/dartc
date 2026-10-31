import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

ArgumentList arguments(SyntaxFixture f, int start, [String? name]) {
  final end = f.at(')', start) + 1;
  final expression = name == null ? null : f.reference(name, start);
  return ArgumentList(
    source: f.source,
    start: start,
    end: end,
    arguments: [
      if (expression != null)
        Argument(
          source: f.source,
          start: expression.start,
          end: expression.end,
          value: expression,
        ),
    ],
  );
}

EmptyFunctionBody semicolon(SyntaxFixture f, [int from = 0]) =>
    EmptyFunctionBody(
      source: f.source,
      start: f.at(';', from),
      end: f.at(';', from) + 1,
    );

void main() {
  group('Constructors', () {
    test('retains traditional and abbreviated declaration names without resolving them', () {
      for (final (text, keyword, names, isConst, isExternal)
          in <(String, ConstructorKeyword, List<String>, bool, bool)>[
            ('C();', .none, ['C'], false, false),
            ('const C.named();', .none, ['C', 'named'], true, false),
            ('external C.new();', .none, ['C', 'new'], false, true),
            ('new();', .newKeyword, [], false, false),
            ('const new named();', .newKeyword, ['named'], true, false),
            ('external factory();', .factoryKeyword, [], false, true),
            ('external factory C();', .factoryKeyword, ['C'], false, true),
            (
              'external factory named();',
              .factoryKeyword,
              ['named'],
              false,
              true,
            ),
          ]) {
        final f = SyntaxFixture(text);
        final nameNodes = [for (final name in names) f.id(name)];
        final node = ConstructorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          keyword: keyword,
          isConst: isConst,
          isExternal: isExternal,
          name: nameNodes,
          parameters: f.emptyParameters(f.at('()')),
          body: semicolon(f),
        );
        nameNodes.clear();
        checkTree(node);
        expect(node.name.map((n) => n.text), names);
        expect(node.keyword, keyword);
        expect(node.isConst, isConst);
        expect(node.isExternal, isExternal);
        expect(node.body, isA<FunctionBody>());
        expect(() => node.name.clear(), throwsUnsupportedError);
      }
    });

    test('preserves field, assertion and super initializer order and argument identity', () {
      final f = SyntaxFixture(
        '@tag C(int x) : this.x = x, assert(ready, "bad"), super.named(x);',
      );
      final metadata = [f.annotation('tag')];
      final field = FieldInitializer(
        source: f.source,
        start: f.at('this.x'),
        end: f.at(', assert'),
        hasThis: true,
        name: f.id('x', f.at('this.x')),
        value: f.reference('x', f.at('= x')),
      );
      final assertion = AssertInitializer(
        source: f.source,
        start: f.at('assert'),
        end: f.at(', super'),
        condition: f.reference('ready'),
        message: f.string('"bad"'),
      );
      final superArgs = arguments(f, f.at('(', f.at('super.')), 'x');
      final superCall = SuperConstructorInitializer(
        source: f.source,
        start: f.at('super.'),
        end: superArgs.end,
        name: f.id('named'),
        arguments: superArgs,
      );
      final initializers = <ConstructorInitializer>[
        field,
        assertion,
        superCall,
      ];
      final node = ConstructorDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        name: [f.id('C')],
        parameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [f.parameter('x', type: f.type('int'))],
        ),
        initializers: initializers,
        body: semicolon(f),
      );
      metadata.clear();
      initializers.clear();
      checkTree(node);
      expect(
        [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
        [
          '@tag',
          'C',
          '(int x)',
          'this.x = x',
          'assert(ready, "bad")',
          'super.named(x)',
          ';',
        ],
      );
      expect(field.hasThis, isTrue);
      expect(superCall.arguments, same(superArgs));
      expect(() => node.initializers.clear(), throwsUnsupportedError);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      expect(walk(node).whereType<IdentifierExpression>().map((n) => n.text), [
        'x',
        'ready',
        'x',
      ]);
    });

    test(
      'represents omitted this, assert messages and super constructor names',
      () {
        final f = SyntaxFixture('C() : x = value, assert(ready), super() {}');
        final field = FieldInitializer(
          source: f.source,
          start: f.at('x ='),
          end: f.at(', assert'),
          name: f.id('x'),
          value: f.reference('value'),
        );
        final assertion = AssertInitializer(
          source: f.source,
          start: f.at('assert'),
          end: f.at(', super'),
          condition: f.reference('ready'),
        );
        final superArgs = arguments(f, f.at('(', f.at('super')));
        final superCall = SuperConstructorInitializer(
          source: f.source,
          start: f.at('super'),
          end: superArgs.end,
          arguments: superArgs,
        );
        final node = ConstructorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: [f.id('C')],
          parameters: f.emptyParameters(f.at('()')),
          initializers: [field, assertion, superCall],
          body: f.emptyBlock(f.at('{}')),
        );
        checkTree(node);
        expect(field.hasThis, isFalse);
        expect(assertion.message, isNull);
        expect(superCall.name, isNull);
        expect(superCall.childCount, 1);
        expect(assertion.childCount, 1);
      },
    );

    test(
      'preserves this redirections without converting them to ordinary calls',
      () {
        for (final suffix in ['', '.named']) {
          final f = SyntaxFixture('new zero(int x) : this$suffix(x);');
          final callArgs = arguments(f, f.at('(', f.at('this')), 'x');
          final redirect = RedirectingConstructorInitializer(
            source: f.source,
            start: f.at('this'),
            end: callArgs.end,
            name: suffix.isEmpty ? null : f.id('named'),
            arguments: callArgs,
          );
          final node = ConstructorDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            keyword: .newKeyword,
            name: [f.id('zero')],
            parameters: FormalParameterList(
              source: f.source,
              start: f.at('('),
              end: f.at(')') + 1,
              parameters: [f.parameter('x', type: f.type('int'))],
            ),
            initializers: [redirect],
            body: semicolon(f),
          );
          checkTree(node);
          expect(redirect.arguments, same(callArgs));
          expect(walk(node).whereType<InvocationExpression>(), isEmpty);
          expect(redirect.name?.text, suffix.isEmpty ? null : 'named');
        }
      },
    );

    test('keeps qualified factory targets and type arguments unresolved', () {
      for (final generic in [false, true]) {
        final f = SyntaxFixture(
          generic
              ? 'const factory C() = p.Target<int>.named;'
              : 'const factory C() = p.Target.named;',
        );
        final targetNames = [
          f.id('p'),
          f.id('Target'),
          if (!generic) f.id('named'),
        ];
        final redirect = FactoryRedirectBody(
          source: f.source,
          start: f.at('='),
          end: f.source.length,
          name: targetNames,
          typeArguments: generic
              ? TypeArgumentList(
                  source: f.source,
                  start: f.at('<'),
                  end: f.at('>') + 1,
                  arguments: [f.type('int')],
                )
              : null,
          constructorName: generic ? f.id('named') : null,
        );
        final node = ConstructorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          keyword: .factoryKeyword,
          isConst: true,
          name: [f.id('C')],
          parameters: f.emptyParameters(f.at('()')),
          body: redirect,
        );
        targetNames.clear();
        checkTree(node);
        expect(node.initializers, isEmpty);
        expect(node.body, isNot(isA<FunctionBody>()));
        expect(
          redirect.name.map((n) => n.text),
          generic ? ['p', 'Target'] : ['p', 'Target', 'named'],
        );
        expect(redirect.constructorName?.text, generic ? 'named' : null);
        expect(() => redirect.name.clear(), throwsUnsupportedError);
        expect(
          walk(node).whereType<NamedTypeAnnotation>().map((n) => n.text),
          generic ? ['int'] : <String>[],
        );
      }
    });

    test(
      'factory bodies can return expressions without becoming redirections',
      () {
        final f = SyntaxFixture('factory named() => create();');
        final body = ExpressionFunctionBody(
          source: f.source,
          start: f.at('=>'),
          end: f.source.length,
          expression: f.emptyCall('create'),
        );
        final node = ConstructorDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          keyword: .factoryKeyword,
          name: [f.id('named')],
          parameters: f.emptyParameters(f.at('()')),
          body: body,
        );
        checkTree(node);
        expect(node.body, same(body));
        expect(walk(node).whereType<FactoryRedirectBody>(), isEmpty);
      },
    );

    test(
      'primary body stays in member order separately from header parameters',
      () {
        final f = SyntaxFixture(
          'class C(final int x) { this : assert(ready); }',
        );
        final parameter = FormalParameter(
          source: f.source,
          start: f.at('final'),
          end: f.at(')'),
          kind: .requiredPositional,
          keyword: .finalKeyword,
          type: f.type('int'),
          name: f.id('x'),
        );
        final initializers = <ConstructorInitializer>[
          AssertInitializer(
            source: f.source,
            start: f.at('assert'),
            end: f.at(';'),
            condition: f.reference('ready'),
          ),
        ];
        final body = PrimaryConstructorBody(
          source: f.source,
          start: f.at('this'),
          end: f.at(';') + 1,
          initializers: initializers,
          body: semicolon(f),
        );
        final node = ClassDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('C'),
          primaryParameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: [parameter],
          ),
          members: [body],
        );
        initializers.clear();
        checkTree(node);
        expect(node.childAt(2), same(body));
        expect(walk(node).whereType<FormalParameter>().single, same(parameter));
        expect(() => body.initializers.clear(), throwsUnsupportedError);
        final g = SyntaxFixture('this {}');
        final noInitializers = PrimaryConstructorBody(
          source: g.source,
          start: 0,
          end: g.source.length,
          body: g.emptyBlock(g.at('{}')),
        );
        checkTree(noInitializers);
        expect(noInitializers.childCount, 1);
      },
    );

    test(
      'rejects stale nodes, reordered initializers and invalid body ranges',
      () {
        final f = SyntaxFixture('C() : x = a, y = b;');
        final old = SyntaxFixture(f.source.text);
        final x = FieldInitializer(
          source: f.source,
          start: f.at('x ='),
          end: f.at(','),
          name: f.id('x'),
          value: f.reference('a'),
        );
        final y = FieldInitializer(
          source: f.source,
          start: f.at('y ='),
          end: f.at(';'),
          name: f.id('y'),
          value: f.reference('b'),
        );
        expect(
          () => ConstructorDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: [f.id('C')],
            parameters: f.emptyParameters(f.at('()')),
            initializers: [y, x],
            body: semicolon(f),
          ),
          throwsArgumentError,
        );
        expect(
          () => ConstructorDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: [f.id('C')],
            parameters: f.emptyParameters(f.at('()')),
            body: semicolon(old),
          ),
          throwsArgumentError,
        );
        expect(
          () => PrimaryConstructorBody(
            source: f.source,
            start: 0,
            end: f.source.length,
            initializers: [x, x],
            body: semicolon(f),
          ),
          throwsArgumentError,
        );
        expect(
          () => FieldInitializer(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: f.id('x'),
            value: old.reference('a'),
          ),
          throwsArgumentError,
        );
        expect(
          () => AssertInitializer(
            source: f.source,
            start: 0,
            end: f.source.length,
            condition: old.reference('a'),
          ),
          throwsArgumentError,
        );
        expect(
          () => SuperConstructorInitializer(
            source: f.source,
            start: 0,
            end: f.source.length,
            arguments: arguments(old, old.at('(')),
          ),
          throwsArgumentError,
        );
        expect(
          () => RedirectingConstructorInitializer(
            source: f.source,
            start: 0,
            end: f.source.length,
            arguments: arguments(old, old.at('(')),
          ),
          throwsArgumentError,
        );
        expect(
          () => FactoryRedirectBody(
            source: f.source,
            start: 0,
            end: f.source.length,
            name: [f.id('b'), f.id('a')],
          ),
          throwsArgumentError,
        );
        expect(
          () => ConstructorDeclaration(
            source: f.source,
            start: 0,
            end: f.at(';'),
            name: [f.id('C')],
            parameters: f.emptyParameters(f.at('()')),
            body: semicolon(f),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
