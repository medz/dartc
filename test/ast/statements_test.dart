import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Statement syntax', () {
    test('blocks retain empty statements, calls, optional returns, and immutable order', () {
      final f = SyntaxFixture('{ ; action(); return value; return; }');
      final statements = <Statement>[
        EmptyStatement(source: f.source, start: 2, end: 3),
        f.callStatement('action'),
        ReturnStatement(
          source: f.source,
          start: f.at('return'),
          end: f.at(';', f.at('return')) + 1,
          expression: f.reference('value'),
        ),
        ReturnStatement(
          source: f.source,
          start: f.at('return;'),
          end: f.at('return;') + 7,
        ),
      ];
      final block = BlockStatement(
        source: f.source,
        start: 0,
        end: f.source.length,
        statements: statements,
      );
      statements.clear();
      checkTree(block);
      expect(block.statements.map((s) => s.text), [
        ';',
        'action();',
        'return value;',
        'return;',
      ]);
      expect((block.statements.last as ReturnStatement).expression, isNull);
      expect(() => block.statements.clear(), throwsUnsupportedError);
    });

    test('declaration statements own their semicolon and keep initialization syntax', () {
      final f = SyntaxFixture('{ int x = first(); var (a, b) = pair(); }');
      final firstEnd = f.at(';') + 1;
      final variables = VariableDeclarationList(
        source: f.source,
        start: f.at('int'),
        end: firstEnd - 1,
        type: f.type('int'),
        declarations: [
          VariableDeclaration(
            source: f.source,
            start: f.at('x'),
            end: firstEnd - 1,
            name: f.id('x'),
            initializer: f.emptyCall('first'),
          ),
        ],
      );
      final pattern = RecordPattern(
        source: f.source,
        start: f.at('(a'),
        end: f.at(')', f.at('(a')) + 1,
        fields: [
          f.patternName('a', f.at('(a')),
          f.patternName('b', f.at('(a')),
        ],
      );
      final patternEnd = f.at(';', firstEnd) + 1;
      final declaration = PatternVariableDeclaration(
        source: f.source,
        start: f.at('var'),
        end: patternEnd - 1,
        isFinal: false,
        pattern: pattern,
        initializer: f.emptyCall('pair'),
      );
      final block = BlockStatement(
        source: f.source,
        start: 0,
        end: f.source.length,
        statements: [
          VariableDeclarationStatement(
            source: f.source,
            start: variables.start,
            end: firstEnd,
            variables: variables,
          ),
          PatternVariableDeclarationStatement(
            source: f.source,
            start: declaration.start,
            end: patternEnd,
            declaration: declaration,
          ),
        ],
      );
      checkTree(block);
      expect(block.statements.first.text, 'int x = first();');
      expect(variables.text, 'int x = first()');
      expect(declaration.text, 'var (a, b) = pair()');
      expect(walk(block).whereType<InvocationExpression>().map((e) => e.text), [
        'first()',
        'pair()',
      ]);
    });

    test(
      'if-case preserves guard and a nested else-if branch in source order',
      () {
        final f = SyntaxFixture(
          'if (input() case int x when ready()) yes(); else if (other()) no();',
        );
        final variable = VariablePattern(
          source: f.source,
          start: f.at('int'),
          end: f.at(' when'),
          type: f.type('int'),
          name: f.id('x'),
        );
        final node = IfStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          condition: f.emptyCall('input'),
          casePattern: GuardedPattern(
            source: f.source,
            start: variable.start,
            end: f.at('ready') + 7,
            pattern: variable,
            guard: f.emptyCall('ready'),
          ),
          thenStatement: f.callStatement('yes'),
          elseStatement: IfStatement(
            source: f.source,
            start: f.at('if', f.at('else')),
            end: f.source.length,
            condition: f.emptyCall('other'),
            thenStatement: f.callStatement('no'),
          ),
        );
        checkTree(node);
        expect(node.childCount, 4);
        expect((node.elseStatement as IfStatement).elseStatement, isNull);
        expect(
          walk(node).whereType<InvocationExpression>().map((e) => e.text),
          ['input()', 'ready()', 'yes()', 'other()', 'no()'],
        );
      },
    );

    test('represents every optional if branch without invented syntax', () {
      for (final hasCase in [false, true]) {
        for (final hasElse in [false, true]) {
          final f = SyntaxFixture(
            'if (value${hasCase ? ' case _' : ''}) ;${hasElse ? ' else ;' : ''}',
          );
          final pattern = hasCase
              ? WildcardPattern(
                  source: f.source,
                  start: f.at('_'),
                  end: f.at('_') + 1,
                )
              : null;
          final thenStatement = EmptyStatement(
            source: f.source,
            start: f.at(';'),
            end: f.at(';') + 1,
          );
          final elseStatement = hasElse
              ? EmptyStatement(
                  source: f.source,
                  start: f.source.length - 1,
                  end: f.source.length,
                )
              : null;
          final node = IfStatement(
            source: f.source,
            start: 0,
            end: f.source.length,
            condition: f.reference('value'),
            casePattern: pattern,
            thenStatement: thenStatement,
            elseStatement: elseStatement,
          );
          checkTree(node);
          expect(
            [for (var i = 0; i < node.childCount; i++) node.childAt(i)],
            [node.condition, ?pattern, thenStatement, ?elseStatement],
          );
        }
      }
    });

    test('while and do-while retain their different written child orders', () {
      final f = SyntaxFixture(
        'while (ready()) step(); do tick(); while (again());',
      );
      final loop = WhileStatement(
        source: f.source,
        start: 0,
        end: f.at(';') + 1,
        condition: f.emptyCall('ready'),
        body: f.callStatement('step'),
      );
      final doLoop = DoStatement(
        source: f.source,
        start: f.at('do'),
        end: f.source.length,
        body: f.callStatement('tick'),
        condition: f.emptyCall('again'),
      );
      checkTree(loop);
      checkTree(doLoop);
      expect(walk(loop).whereType<InvocationExpression>().map((n) => n.text), [
        'ready()',
        'step()',
      ]);
      expect(
        walk(doLoop).whereType<InvocationExpression>().map((n) => n.text),
        ['tick()', 'again()'],
      );
    });

    test('reuses loop headers for statement bodies and retains await', () {
      final f = SyntaxFixture('for (;;) ; await for (value in values) use();');
      final first = ForStatement(
        source: f.source,
        start: 0,
        end: f.at(' await'),
        parts: ForParts(source: f.source, start: 5, end: 7),
        body: EmptyStatement(source: f.source, start: 9, end: 10),
      );
      final second = ForStatement(
        source: f.source,
        start: f.at('await'),
        end: f.source.length,
        isAwait: true,
        parts: ForInParts(
          source: f.source,
          start: f.at('value'),
          end: f.at(') use'),
          target: f.id('value'),
          iterable: f.reference('values'),
        ),
        body: f.callStatement('use'),
      );
      checkTree(first);
      checkTree(second);
      expect((first.parts as ForParts).condition, isNull);
      expect(walk(first).whereType<LiteralExpression>(), isEmpty);
      expect(second.isAwait, isTrue);
      expect((second.parts as ForInParts).target.text, 'value');
    });

    test(
      'preserves multiple labels and jump references without binding them',
      () {
        final f = SyntaxFixture(
          'outer: inner: { continue outer; break inner; break; continue; }',
        );
        final labelList = [
          for (final name in ['outer', 'inner'])
            Label(
              source: f.source,
              start: f.at(name),
              end: f.at(name) + name.length + 1,
              name: f.id(name),
            ),
        ];
        final body = BlockStatement(
          source: f.source,
          start: f.at('{'),
          end: f.source.length,
          statements: [
            ContinueStatement(
              source: f.source,
              start: f.at('continue'),
              end: f.at(';') + 1,
              label: f.id('outer', f.at('{')),
            ),
            BreakStatement(
              source: f.source,
              start: f.at('break'),
              end: f.at(';', f.at('break')) + 1,
              label: f.id('inner', f.at('{')),
            ),
            BreakStatement(
              source: f.source,
              start: f.at('break;'),
              end: f.at('break;') + 6,
            ),
            ContinueStatement(
              source: f.source,
              start: f.at('continue;'),
              end: f.at('continue;') + 9,
            ),
          ],
        );
        final node = LabeledStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          labels: labelList,
          statement: body,
        );
        labelList.clear();
        checkTree(node);
        expect(node.labels.map((n) => n.text), ['outer:', 'inner:']);
        expect(walk(node).whereType<Identifier>().map((n) => n.text), [
          'outer',
          'inner',
          'outer',
          'inner',
        ]);
        expect(() => node.labels.clear(), throwsUnsupportedError);
      },
    );

    test(
      'keeps assertions and yield forms distinct without evaluating operands',
      () {
        final f = SyntaxFixture(
          '{ assert(check()); assert(other(), message()); yield value; yield* values; }',
        );
        final secondAssert = f.at('assert', f.at(';'));
        final block = BlockStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          statements: [
            AssertStatement(
              source: f.source,
              start: f.at('assert'),
              end: f.at(';') + 1,
              condition: f.emptyCall('check'),
            ),
            AssertStatement(
              source: f.source,
              start: secondAssert,
              end: f.at(';', secondAssert) + 1,
              condition: f.emptyCall('other'),
              message: f.emptyCall('message'),
            ),
            YieldStatement(
              source: f.source,
              start: f.at('yield'),
              end: f.at(';', f.at('yield')) + 1,
              expression: f.reference('value', f.at('yield')),
            ),
            YieldStatement(
              source: f.source,
              start: f.at('yield*'),
              end: f.at(';', f.at('yield*')) + 1,
              isStar: true,
              expression: f.reference('values'),
            ),
          ],
        );
        checkTree(block);
        expect(walk(block).whereType<YieldStatement>().map((s) => s.isStar), [
          false,
          true,
        ]);
        expect(
          walk(block).whereType<InvocationExpression>().map((s) => s.text),
          ['check()', 'other()', 'message()'],
        );
      },
    );

    test('rejects stale, overlapping, and reversed children while preserving missing statements', () {
      final f = SyntaxFixture('{} ready()');
      final old = SyntaxFixture('{} ready()');
      final missing = MissingStatement(
        source: f.source,
        offset: f.source.length,
      );
      checkTree(missing);
      expect(missing.length, 0);
      expect(
        () => MissingStatement(source: f.source, offset: -1),
        throwsRangeError,
      );
      expect(
        () => BlockStatement(
          source: f.source,
          start: 0,
          end: 2,
          statements: [old.emptyBlock(0)],
        ),
        throwsArgumentError,
      );
      expect(
        () => WhileStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          condition: f.emptyCall('ready'),
          body: f.emptyBlock(0),
        ),
        throwsArgumentError,
      );
      expect(
        () => BlockStatement(
          source: f.source,
          start: 0,
          end: 2,
          statements: [f.emptyBlock(0), f.emptyBlock(0)],
        ),
        throwsArgumentError,
      );
    });
  });
}
