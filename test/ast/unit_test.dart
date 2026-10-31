import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Compilation units', () {
    test('covers the full snapshot and preserves script tags, trivia, and member order', () {
      final f = SyntaxFixture(
        '\uFEFF#!/usr/bin/env dart\r\n// 😀\r\nlibrary demo;\nimport "dep.dart";\nint f() => 1;\n',
      );
      final scriptTag = ScriptTag(source: f.source, start: 1, end: f.at('\r'));
      final members = <CompilationUnitMember>[
        LibraryDirective(
          source: f.source,
          start: f.at('library'),
          end: f.at(';') + 1,
          name: DottedName(
            source: f.source,
            start: f.at('demo'),
            end: f.at('demo') + 4,
            components: [f.id('demo')],
          ),
        ),
        ImportDirective(
          source: f.source,
          start: f.at('import'),
          end: f.at(';', f.at('import')) + 1,
          uri: f.string('"dep.dart"'),
        ),
        TopLevelFunctionDeclaration(
          source: f.source,
          start: f.at('int f'),
          end: f.at(';', f.at('int f')) + 1,
          returnType: f.type('int'),
          name: f.id('f', f.at('int f')),
          parameters: f.emptyParameters(f.at('()')),
          body: ExpressionFunctionBody(
            source: f.source,
            start: f.at('=>'),
            end: f.at(';', f.at('=>')) + 1,
            expression: f.literal('1'),
          ),
        ),
      ];
      final unit = CompilationUnit(
        source: f.source,
        scriptTag: scriptTag,
        members: members,
      );
      members.clear();
      checkTree(unit);
      expect(unit.start, 0);
      expect(unit.end, f.source.length);
      expect(unit.text, f.source.text);
      expect(unit.childAt(0), same(scriptTag));
      expect(scriptTag.text, '#!/usr/bin/env dart');
      expect(unit.members.map((m) => m.text), [
        'library demo;',
        'import "dep.dart";',
        'int f() => 1;',
      ]);
      expect(() => unit.members.clear(), throwsUnsupportedError);
    });

    test('empty and comment-only files need no invented syntax nodes', () {
      for (final text in ['', ' \n// @dart=3.13\n/* comment */\r\n']) {
        final f = SyntaxFixture(text);
        final unit = CompilationUnit(source: f.source, members: []);
        checkTree(unit);
        expect(unit.scriptTag, isNull);
        expect(unit.childCount, 0);
        expect(unit.length, text.length);
        expect(walk(unit), [unit]);
      }
    });

    test(
      'retains a misplaced directive after a declaration for later diagnostics',
      () {
        final f = SyntaxFixture("f() {} import 'late.dart';");
        final declaration = TopLevelFunctionDeclaration(
          source: f.source,
          start: 0,
          end: 6,
          name: f.id('f'),
          parameters: f.emptyParameters(1),
          body: f.emptyBlock(4),
        );
        final directive = ImportDirective(
          source: f.source,
          start: f.at('import'),
          end: f.source.length,
          uri: f.string("'late.dart'"),
        );
        final unit = CompilationUnit(
          source: f.source,
          members: [declaration, directive],
        );
        checkTree(unit);
        expect(unit.childAt(0), same(declaration));
        expect(unit.childAt(1), same(directive));
        expect(
          () => CompilationUnit(
            source: f.source,
            members: [directive, declaration],
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects mixed snapshots, repeated members, and script tags after members', () {
      final f = SyntaxFixture('library;');
      final old = SyntaxFixture(f.source.text);
      final directive = LibraryDirective(
        source: f.source,
        start: 0,
        end: f.source.length,
      );
      expect(
        () => CompilationUnit(source: old.source, members: [directive]),
        throwsArgumentError,
      );
      expect(
        () =>
            CompilationUnit(source: f.source, members: [directive, directive]),
        throwsArgumentError,
      );
      expect(
        () => CompilationUnit(
          source: f.source,
          scriptTag: ScriptTag(source: f.source, start: 3, end: 7),
          members: [directive],
        ),
        throwsArgumentError,
      );
    });
  });
}
