import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  statementTests();
  test(
    'keeps selection, guarded pattern, result, and fallback in source order',
    () {
      final f = SyntaxFixture(
        'switch (input()) { int value when ready() => use(value), _ => fallback() }',
      );
      final input = f.emptyCall('input');
      final value = VariablePattern(
        source: f.source,
        start: f.at('int value'),
        end: f.at('value') + 5,
        type: f.type('int', from: f.at('{')),
        name: f.id('value'),
      );
      final guard = f.emptyCall('ready');
      final guarded = GuardedPattern(
        source: f.source,
        start: value.start,
        end: guard.end,
        pattern: value,
        guard: guard,
      );
      final callee = f.reference('use');
      final argument = f.reference('value', callee.end);
      final call = InvocationExpression(
        source: f.source,
        start: callee.start,
        end: argument.end + 1,
        callee: callee,
        arguments: ArgumentList(
          source: f.source,
          start: callee.end,
          end: argument.end + 1,
          arguments: [
            Argument(
              source: f.source,
              start: argument.start,
              end: argument.end,
              value: argument,
            ),
          ],
        ),
      );
      final wildcard = WildcardPattern(
        source: f.source,
        start: f.at('_'),
        end: f.at('_') + 1,
      );
      final fallback = f.emptyCall('fallback');
      final cases = [
        SwitchExpressionCase(
          source: f.source,
          start: guarded.start,
          end: call.end,
          pattern: guarded,
          value: call,
        ),
        SwitchExpressionCase(
          source: f.source,
          start: wildcard.start,
          end: fallback.end,
          pattern: wildcard,
          value: fallback,
        ),
      ];
      final root = SwitchExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        expression: input,
        cases: cases,
      );
      cases.clear();
      checkTree(root);
      expect(root.cases.last.pattern, same(wildcard));
      expect(walk(root).whereType<InvocationExpression>(), [
        input,
        guard,
        call,
        fallback,
      ]);
      expect(walk(root).whereType<GuardedPattern>(), [guarded]);
      expect(() => root.cases.clear(), throwsUnsupportedError);
    },
  );

  test('rejects guard-before-pattern and result-before-case ranges', () {
    final f = SyntaxFixture('a b');
    expect(
      () => GuardedPattern(
        source: f.source,
        start: 0,
        end: 3,
        pattern: f.patternName('b'),
        guard: f.reference('a'),
      ),
      throwsArgumentError,
    );
    expect(
      () => SwitchExpressionCase(
        source: f.source,
        start: 0,
        end: 3,
        pattern: f.patternName('b'),
        value: f.reference('a'),
      ),
      throwsArgumentError,
    );
  });
}

void statementTests() {
  group('Switch statement syntax', () {
    test(
      'retains labeled and empty cases, guards, default, and jump references',
      () {
        final f = SyntaxFixture(
          'switch (input()) { first: case 1: case int x when ready(): continue first; default: break; }',
        );
        final labels = [
          Label(
            source: f.source,
            start: f.at('first:'),
            end: f.at('first:') + 6,
            name: f.id('first'),
          ),
        ];
        final members = [
          SwitchStatementMember(
            source: f.source,
            start: f.at('first:'),
            end: f.at(': case', f.at('case 1')) + 1,
            labels: labels,
            pattern: ConstantPattern(
              source: f.source,
              start: f.at('1'),
              end: f.at('1') + 1,
              expression: f.literal('1'),
            ),
            statements: [],
          ),
          SwitchStatementMember(
            source: f.source,
            start: f.at('case int'),
            end: f.at(';') + 1,
            pattern: GuardedPattern(
              source: f.source,
              start: f.at('int'),
              end: f.at('ready') + 7,
              pattern: VariablePattern(
                source: f.source,
                start: f.at('int'),
                end: f.at(' when'),
                type: f.type('int'),
                name: f.id('x'),
              ),
              guard: f.emptyCall('ready'),
            ),
            statements: [
              ContinueStatement(
                source: f.source,
                start: f.at('continue'),
                end: f.at(';') + 1,
                label: f.id('first', f.at('continue')),
              ),
            ],
          ),
          SwitchStatementMember(
            source: f.source,
            start: f.at('default'),
            end: f.at('break;') + 6,
            statements: [
              BreakStatement(
                source: f.source,
                start: f.at('break'),
                end: f.at('break') + 6,
              ),
            ],
          ),
        ];
        final node = SwitchStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          expression: f.emptyCall('input'),
          members: members,
        );
        members.clear();
        labels.clear();
        checkTree(node);
        expect(node.members.first.statements, isEmpty);
        expect(node.members.first.labels.single.text, 'first:');
        expect(node.members.last.pattern, isNull);
        expect(node.members[1].pattern, isA<GuardedPattern>());
        expect(
          walk(node).whereType<InvocationExpression>().map((e) => e.text),
          ['input()', 'ready()'],
        );
        expect(() => node.members.clear(), throwsUnsupportedError);
        expect(() => node.members.first.labels.clear(), throwsUnsupportedError);
        expect(
          () => node.members[1].statements.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'retains an empty switch and a labeled default with no statements',
      () {
        final f = SyntaxFixture('switch (value) {}');
        final node = SwitchStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          expression: f.reference('value'),
          members: [],
        );
        checkTree(node);
        expect(node.childCount, 1);
        final g = SyntaxFixture('end: default:');
        final member = SwitchStatementMember(
          source: g.source,
          start: 0,
          end: g.source.length,
          labels: [
            Label(source: g.source, start: 0, end: 4, name: g.id('end')),
          ],
          statements: [],
        );
        checkTree(member);
        expect(member.childCount, 1);
        expect(member.pattern, isNull);
      },
    );

    test('rejects a member before its selector and stale statement bodies', () {
      final f = SyntaxFixture('default: ; value');
      final old = SyntaxFixture(f.source.text);
      final member = SwitchStatementMember(
        source: f.source,
        start: 0,
        end: 10,
        statements: [EmptyStatement(source: f.source, start: 9, end: 10)],
      );
      expect(
        () => SwitchStatement(
          source: f.source,
          start: 0,
          end: f.source.length,
          expression: f.reference('value'),
          members: [member],
        ),
        throwsArgumentError,
      );
      expect(
        () => SwitchStatementMember(
          source: f.source,
          start: 0,
          end: 10,
          statements: [EmptyStatement(source: old.source, start: 9, end: 10)],
        ),
        throwsArgumentError,
      );
    });
  });
}
