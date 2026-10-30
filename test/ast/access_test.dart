import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'keeps outer and nested cascade receivers and section order separate',
    () {
      final f = SyntaxFixture(
        'make()?..slot = (other()..[key()] += value())..finish()',
      );
      final target = f.emptyCall('make');
      final first = CascadePropertyExpression(
        source: f.source,
        start: f.at('?..'),
        end: f.at('slot') + 4,
        property: f.id('slot'),
      );
      final innerTarget = f.emptyCall('other');
      final innerIndex = CascadeIndexExpression(
        source: f.source,
        start: f.at('..['),
        end: f.at(']') + 1,
        index: f.emptyCall('key'),
      );
      final innerValue = f.emptyCall('value');
      final innerAssignment = AssignmentExpression(
        source: f.source,
        start: innerIndex.start,
        end: innerValue.end,
        left: innerIndex,
        op: .add,
        right: innerValue,
      );
      final inner = CascadeExpression(
        source: f.source,
        start: innerTarget.start,
        end: innerValue.end,
        target: innerTarget,
        sections: [innerAssignment],
      );
      final parens = ParenthesizedExpression(
        source: f.source,
        start: inner.start - 1,
        end: inner.end + 1,
        expression: inner,
      );
      final assignment = AssignmentExpression(
        source: f.source,
        start: first.start,
        end: parens.end,
        left: first,
        op: .assign,
        right: parens,
      );
      final last = CascadePropertyExpression(
        source: f.source,
        start: f.at('..finish'),
        end: f.at('finish') + 6,
        property: f.id('finish'),
      );
      final call = InvocationExpression(
        source: f.source,
        start: last.start,
        end: f.source.length,
        callee: last,
        arguments: ArgumentList(
          source: f.source,
          start: last.end,
          end: f.source.length,
          arguments: [],
        ),
      );
      final sections = <Expression>[assignment, call];
      final root = CascadeExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        target: target,
        isNullAware: true,
        sections: sections,
      );
      sections.clear();
      checkTree(root);
      expect(root.sections, [assignment, call]);
      expect(() => root.sections.clear(), throwsUnsupportedError);
      expect(root.isNullAware, isTrue);
      expect(inner.isNullAware, isFalse);
      expect(
        root.sections.first.text,
        '?..slot = (other()..[key()] += value())',
      );
      expect(walk(root).whereType<Identifier>().map((n) => n.text), [
        'make',
        'slot',
        'other',
        'key',
        'value',
        'finish',
      ]);
      expect(walk(root).whereType<InvocationExpression>().map((n) => n.text), [
        'make()',
        'other()',
        'key()',
        'value()',
        '..finish()',
      ]);
      expect(walk(root).whereType<CascadeExpression>(), [root, inner]);
      expect(walk(root).where((n) => identical(n, target)).length, 1);
      expect(walk(root).where((n) => identical(n, innerTarget)).length, 1);
    },
  );

  test(
    'distinguishes null-aware cascade indexing from a null-aware selector',
    () {
      final f = SyntaxFixture('items?..[key()]?[next()]');
      final head = CascadeIndexExpression(
        source: f.source,
        start: f.at('?..'),
        end: f.at(']') + 1,
        index: f.emptyCall('key'),
      );
      final tail = IndexExpression(
        source: f.source,
        start: head.start,
        end: f.source.length,
        target: head,
        index: f.emptyCall('next'),
        isNullAware: true,
      );
      final root = CascadeExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        target: f.reference('items'),
        isNullAware: true,
        sections: [tail],
      );
      checkTree(root);
      expect(head.text, '?..[key()]');
      expect(tail.text, '?..[key()]?[next()]');
      expect(tail.target, same(head));
      expect(root.isNullAware, isTrue);
      expect(tail.isNullAware, isTrue);
      expect(walk(root).whereType<Identifier>().map((n) => n.text), [
        'items',
        'key',
        'next',
      ]);
    },
  );

  test(
    'retains the complete dot-shorthand chain as one contextual boundary',
    () {
      final f = SyntaxFixture('.tryParse(input)?.abs()!');
      final head = DotShorthandReferenceExpression(
        source: f.source,
        start: 0,
        end: f.at('('),
        name: f.id('tryParse'),
      );
      final firstCall = InvocationExpression(
        source: f.source,
        start: 0,
        end: f.at(')') + 1,
        callee: head,
        arguments: ArgumentList(
          source: f.source,
          start: head.end,
          end: f.at(')') + 1,
          arguments: [
            Argument(
              source: f.source,
              start: f.at('input'),
              end: f.at('input') + 5,
              value: f.reference('input'),
            ),
          ],
        ),
      );
      final access = PropertyAccessExpression(
        source: f.source,
        start: 0,
        end: f.at('abs') + 3,
        target: firstCall,
        property: f.id('abs'),
        isNullAware: true,
      );
      final call = InvocationExpression(
        source: f.source,
        start: 0,
        end: f.at('!'),
        callee: access,
        arguments: ArgumentList(
          source: f.source,
          start: access.end,
          end: f.at('!'),
          arguments: [],
        ),
      );
      final root = DotShorthandExpression(
        source: f.source,
        start: 0,
        end: f.source.length,
        expression: NullAssertionExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          operand: call,
        ),
      );
      checkTree(root);
      expect(root.text, '.tryParse(input)?.abs()!');
      expect(head.text, '.tryParse');
      expect(walk(root).whereType<DotShorthandExpression>(), [root]);
      expect(walk(root).whereType<Identifier>().map((n) => n.text), [
        'tryParse',
        'input',
        'abs',
      ]);
    },
  );

  test('keeps parentheses outside a shorthand context boundary', () {
    final f = SyntaxFixture('(.new)');
    final head = DotShorthandReferenceExpression(
      source: f.source,
      start: 1,
      end: 5,
      name: f.id('new'),
    );
    final shorthand = DotShorthandExpression(
      source: f.source,
      start: 1,
      end: 5,
      expression: head,
    );
    final root = ParenthesizedExpression(
      source: f.source,
      start: 0,
      end: 6,
      expression: shorthand,
    );
    checkTree(root);
    expect(root.text, '(.new)');
    expect(shorthand.text, '.new');
    expect(walk(root), [root, shorthand, head, head.name]);
  });

  test('keeps explicit const shorthand heads distinct from references', () {
    final f = SyntaxFixture('const .new(1)');
    final head = ConstDotShorthandExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      name: f.id('new'),
      arguments: ArgumentList(
        source: f.source,
        start: f.at('('),
        end: f.source.length,
        arguments: [
          Argument(
            source: f.source,
            start: f.at('1'),
            end: f.at('1') + 1,
            value: f.literal('1'),
          ),
        ],
      ),
    );
    final root = DotShorthandExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      expression: head,
    );
    checkTree(root);
    expect(walk(root).whereType<DotShorthandReferenceExpression>(), isEmpty);
    expect(head.name.text, 'new');
    expect(head.arguments.text, '(1)');
  });

  test(
    'rejects reused receivers, overlapping sections, and stale shorthand heads',
    () {
      final f = SyntaxFixture('x..y..z');
      final receiver = f.reference('x');
      final first = CascadePropertyExpression(
        source: f.source,
        start: 1,
        end: 4,
        property: f.id('y'),
      );
      expect(
        () => CascadeExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          target: receiver,
          sections: [receiver],
        ),
        throwsArgumentError,
      );
      expect(
        () => CascadeExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          target: receiver,
          sections: [first, first],
        ),
        throwsArgumentError,
      );
      final original = SyntaxFixture('.new');
      final replacement = SyntaxFixture('.new');
      expect(
        () => DotShorthandExpression(
          source: replacement.source,
          start: 0,
          end: 4,
          expression: DotShorthandReferenceExpression(
            source: original.source,
            start: 0,
            end: 4,
            name: original.id('new'),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
