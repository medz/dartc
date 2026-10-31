import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Extension declarations', () {
    test('retains named generic extensions and ordered members', () {
      final f = SyntaxFixture(
        '@tag extension Values<T> on List<T> { T get first; void reset(); }',
      );
      final metadata = [f.annotation('tag')];
      final members = <ClassMember>[
        GetterDeclaration(
          source: f.source,
          start: f.at('T get'),
          end: f.at(';') + 1,
          returnType: f.type('T', from: f.at('{')),
          name: f.id('first'),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';'),
            end: f.at(';') + 1,
          ),
        ),
        MethodDeclaration(
          source: f.source,
          start: f.at('void'),
          end: f.at(';', f.at('void')) + 1,
          returnType: f.type('void'),
          name: f.id('reset'),
          parameters: f.emptyParameters(f.at('()')),
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';', f.at('void')),
            end: f.at(';', f.at('void')) + 1,
          ),
        ),
      ];
      final node = ExtensionDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        name: f.id('Values'),
        typeParameters: _typeParameters(f),
        onType: NamedTypeAnnotation(
          source: f.source,
          start: f.at('List'),
          end: f.at('List') + 7,
          name: f.id('List'),
          typeArguments: TypeArgumentList(
            source: f.source,
            start: f.at('<T>', f.at('List')),
            end: f.at('List') + 7,
            arguments: [f.type('T', from: f.at('List'))],
          ),
        ),
        members: members,
      );
      metadata.clear();
      members.clear();
      checkTree(CompilationUnit(source: f.source, members: [node]));
      expect(_children(node), [
        '@tag',
        'Values',
        '<T>',
        'List<T>',
        'T get first;',
        'void reset();',
      ]);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      expect(() => node.members.clear(), throwsUnsupportedError);
    });

    test(
      'keeps anonymous names absent and permits non-class receiver types',
      () {
        for (final text in [
          'extension on int Function(String) {}',
          'extension<T> on (int,);',
          'extension on Object?;',
        ]) {
          final f = SyntaxFixture(text);
          final TypeAnnotation onType = text.contains('Function')
              ? _functionType(f)
              : text.contains('(int,')
              ? _recordType(f)
              : f.type('Object', nullable: true);
          final node = ExtensionDeclaration(
            source: f.source,
            start: 0,
            end: f.source.length,
            typeParameters: text.contains('<T>') ? _typeParameters(f) : null,
            onType: onType,
            isSemicolonBody: text.endsWith(';'),
          );
          checkTree(node);
          expect(node.name, isNull);
          expect(node.onType, same(onType));
          expect(node.members, isEmpty);
          expect(node.isSemicolonBody, text.endsWith(';'));
          expect(node.childCount, text.contains('<T>') ? 2 : 1);
        }
      },
    );

    test('rejects stale receivers and reversed members or header children', () {
      const text = 'extension E<T> on int { int get a; int get b; }';
      final f = SyntaxFixture(text);
      final old = SyntaxFixture(text);
      ExtensionDeclaration make({
        TypeAnnotation? onType,
        Identifier? name,
        TypeParameterList? parameters,
        List<ClassMember> members = const [],
      }) => ExtensionDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        name: name ?? f.id('E'),
        typeParameters: parameters,
        onType: onType ?? f.type('int'),
        members: members,
      );
      GetterDeclaration member(String name) {
        final start = f.at('int get $name');
        final semicolon = f.at(';', start);
        return GetterDeclaration(
          source: f.source,
          start: start,
          end: semicolon + 1,
          returnType: f.type('int', from: start),
          name: f.id(name, start),
          body: EmptyFunctionBody(
            source: f.source,
            start: semicolon,
            end: semicolon + 1,
          ),
        );
      }

      expect(() => make(onType: old.type('int')), throwsArgumentError);
      expect(
        () => make(name: f.id('T'), parameters: _typeParameters(f)),
        throwsArgumentError,
      );
      expect(
        () => make(members: [member('b'), member('a')]),
        throwsArgumentError,
      );
    });

    test(
      'explicit extension applications retain ordinary unresolved call syntax',
      () {
        final f = SyntaxFixture('p.Ex<int>(value).twice');
        final callee = PropertyAccessExpression(
          source: f.source,
          start: 0,
          end: f.at('<'),
          target: f.reference('p'),
          property: f.id('Ex'),
        );
        final invocation = InvocationExpression(
          source: f.source,
          start: 0,
          end: f.at(')') + 1,
          callee: callee,
          typeArguments: TypeArgumentList(
            source: f.source,
            start: f.at('<'),
            end: f.at('>') + 1,
            arguments: [f.type('int')],
          ),
          arguments: ArgumentList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            arguments: [
              Argument(
                source: f.source,
                start: f.at('value'),
                end: f.at(')'),
                value: f.reference('value'),
              ),
            ],
          ),
        );
        final node = PropertyAccessExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          target: invocation,
          property: f.id('twice'),
        );
        checkTree(node);
        expect(_children(node), ['p.Ex<int>(value)', 'twice']);
        expect(_children(invocation), ['p.Ex', '<int>', '(value)']);
        expect(invocation.callee, same(callee));
      },
    );
  });

  group('Extension type declarations', () {
    test('retains representation metadata and primary bodies without synthetic fields', () {
      final f = SyntaxFixture(
        '@tag extension type const E<T>.named(@rep final T value) implements I { this : assert(ready); }',
      );
      final metadata = [f.annotation('tag')];
      final representation = FormalParameter(
        source: f.source,
        start: f.at('@rep'),
        end: f.at(')'),
        metadata: [f.annotation('rep')],
        kind: .requiredPositional,
        keyword: .finalKeyword,
        type: f.type('T', from: f.at('@rep')),
        name: f.id('value'),
      );
      final members = <ClassMember>[
        PrimaryConstructorBody(
          source: f.source,
          start: f.at('this'),
          end: f.at(';') + 1,
          initializers: [
            AssertInitializer(
              source: f.source,
              start: f.at('assert'),
              end: f.at(';'),
              condition: f.reference('ready'),
            ),
          ],
          body: EmptyFunctionBody(
            source: f.source,
            start: f.at(';'),
            end: f.at(';') + 1,
          ),
        ),
      ];
      final node = ExtensionTypeDeclaration(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: metadata,
        isConst: true,
        name: f.id('E'),
        typeParameters: _typeParameters(f),
        primaryConstructorName: f.id('named'),
        primaryParameters: FormalParameterList(
          source: f.source,
          start: f.at('('),
          end: f.at(')') + 1,
          parameters: [representation],
        ),
        implementsClause: TypeListClause(
          source: f.source,
          start: f.at('implements'),
          end: f.at(' {'),
          kind: .implementsKeyword,
          types: [f.type('I')],
        ),
        members: members,
      );
      metadata.clear();
      members.clear();
      checkTree(CompilationUnit(source: f.source, members: [node]));
      expect(_children(node), [
        '@tag',
        'E',
        '<T>',
        'named',
        '(@rep final T value)',
        'implements I',
        'this : assert(ready);',
      ]);
      expect(node.primaryParameters.parameters.single, same(representation));
      expect(node.isConst, isTrue);
      expect(walk(node).whereType<FieldDeclaration>(), isEmpty);
      expect(walk(node).whereType<ConstructorDeclaration>(), isEmpty);
      expect(() => node.metadata.clear(), throwsUnsupportedError);
      expect(() => node.members.clear(), throwsUnsupportedError);
    });

    test('keeps written new names, omitted final, and arbitrary representation types', () {
      for (final text in [
        'extension type E.new(int value);',
        'extension type E(int Function(String) value) {}',
        'extension type E((int,) value) {}',
      ]) {
        final f = SyntaxFixture(text);
        final TypeAnnotation type = text.contains('Function')
            ? _functionType(f)
            : text.contains('(int,)')
            ? _recordType(f)
            : f.type('int');
        final node = ExtensionTypeDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('E'),
          primaryConstructorName: text.contains('.new') ? f.id('new') : null,
          primaryParameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at('value)') + 6,
            parameters: [f.parameter('value', type: type)],
          ),
          isSemicolonBody: text.endsWith(';'),
        );
        checkTree(node);
        expect(
          node.primaryParameters.parameters.single.keyword,
          VariableKeyword.none,
        );
        expect(node.primaryParameters.parameters.single.type, same(type));
        expect(
          node.primaryConstructorName?.text,
          text.contains('.new') ? 'new' : null,
        );
        expect(node.isConst, isFalse);
        expect(node.isSemicolonBody, text.endsWith(';'));
        expect(node.members, isEmpty);
      }
    });

    test(
      'preserves syntax requiring later representation-parameter diagnostics',
      () {
        final f = SyntaxFixture('extension type E(var int a, int b) {}');
        final parameters = [
          FormalParameter(
            source: f.source,
            start: f.at('var'),
            end: f.at(','),
            kind: .requiredPositional,
            keyword: .varKeyword,
            type: f.type('int'),
            name: f.id('a', f.at('int')),
          ),
          f.parameter('b', type: f.type('int', from: f.at(','))),
        ];
        final node = ExtensionTypeDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('E'),
          primaryParameters: FormalParameterList(
            source: f.source,
            start: f.at('('),
            end: f.at(')') + 1,
            parameters: parameters,
          ),
        );
        parameters.clear();
        checkTree(node);
        expect(node.primaryParameters.parameters.map((p) => p.name.text), [
          'a',
          'b',
        ]);
        expect(
          node.primaryParameters.parameters.first.keyword,
          VariableKeyword.varKeyword,
        );
        expect(
          () => node.primaryParameters.parameters.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test('rejects stale parameters and reversed header components', () {
      const text = 'extension type E<T>.named(int value) {}';
      final f = SyntaxFixture(text);
      final old = SyntaxFixture(text);
      FormalParameterList parameters(SyntaxFixture f) => FormalParameterList(
        source: f.source,
        start: f.at('('),
        end: f.at(')') + 1,
        parameters: [f.parameter('value', type: f.type('int'))],
      );
      expect(
        () => ExtensionTypeDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('E'),
          primaryParameters: parameters(old),
        ),
        throwsArgumentError,
      );
      expect(
        () => ExtensionTypeDeclaration(
          source: f.source,
          start: 0,
          end: f.source.length,
          name: f.id('E'),
          typeParameters: _typeParameters(f),
          primaryConstructorName: f.id('T'),
          primaryParameters: parameters(f),
        ),
        throwsArgumentError,
      );
    });
  });
}

List<String> _children(AstNode node) => [
  for (var i = 0; i < node.childCount; i++) node.childAt(i).text,
];

TypeParameterList _typeParameters(SyntaxFixture f) => TypeParameterList(
  source: f.source,
  start: f.at('<T>'),
  end: f.at('<T>') + 3,
  parameters: [
    TypeParameter(
      source: f.source,
      start: f.at('<T>') + 1,
      end: f.at('<T>') + 2,
      name: f.id('T', f.at('<T>')),
    ),
  ],
);

FunctionTypeAnnotation _functionType(SyntaxFixture f) {
  final start = f.at('int Function');
  final parametersStart = f.at('(String)');
  return FunctionTypeAnnotation(
    source: f.source,
    start: start,
    end: parametersStart + 8,
    returnType: f.type('int', from: start),
    parameters: FunctionTypeParameterList(
      source: f.source,
      start: parametersStart,
      end: parametersStart + 8,
      parameters: [
        FunctionTypeParameter(
          source: f.source,
          start: parametersStart + 1,
          end: parametersStart + 7,
          kind: .requiredPositional,
          type: f.type('String'),
        ),
      ],
    ),
  );
}

RecordTypeAnnotation _recordType(SyntaxFixture f) {
  final start = f.at('(int,)');
  return RecordTypeAnnotation(
    source: f.source,
    start: start,
    end: start + 6,
    positionalFields: [
      PositionalRecordTypeField(
        source: f.source,
        start: start + 1,
        end: start + 4,
        type: f.type('int', from: start),
      ),
    ],
  );
}
