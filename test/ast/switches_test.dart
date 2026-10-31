import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
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
