import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('keeps null-aware assignment targets and awaited calls once', () {
    final f = SyntaxFixture('a?[key()] ??= await f<int>(value!)');
    final index = IndexExpression(
      source: f.source,
      start: 0,
      end: f.at(']') + 1,
      target: f.reference('a'),
      index: f.emptyCall('key'),
      isNullAware: true,
    );
    final value = NullAssertionExpression(
      source: f.source,
      start: f.at('value'),
      end: f.at('!') + 1,
      operand: f.reference('value'),
    );
    final call = InvocationExpression(
      source: f.source,
      start: f.at('f<int>'),
      end: f.source.length,
      callee: f.reference('f'),
      typeArguments: TypeArgumentList(
        source: f.source,
        start: f.at('<'),
        end: f.at('>') + 1,
        arguments: [f.type('int')],
      ),
      arguments: ArgumentList(
        source: f.source,
        start: f.at('(value'),
        end: f.source.length,
        arguments: [
          Argument(
            source: f.source,
            start: value.start,
            end: value.end,
            value: value,
          ),
        ],
      ),
    );
    final root = AssignmentExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      left: index,
      op: .ifNull,
      right: AwaitExpression(
        source: f.source,
        start: f.at('await'),
        end: call.end,
        expression: call,
      ),
    );
    checkTree(root);
    expect(root.op.spelling, '??=');
    expect(index.isNullAware, isTrue);
    expect(walk(root).whereType<InvocationExpression>().map((n) => n.text), [
      'key()',
      'f<int>(value!)',
    ]);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'a',
      'key',
      'f',
      'int',
      'value',
    ]);
  });

  test(
    'distinguishes prefix and postfix updates without duplicating targets',
    () {
      for (final (text, op, prefix) in [
        ('++this.value', UpdateOperator.increment, true),
        ('this.value--', UpdateOperator.decrement, false),
      ]) {
        final f = SyntaxFixture(text);
        final receiver = ThisExpression(
          source: f.source,
          start: f.at('this'),
          end: f.at('this') + 4,
        );
        final target = PropertyAccessExpression(
          source: f.source,
          start: receiver.start,
          end: f.at('value') + 5,
          target: receiver,
          property: f.id('value'),
        );
        final root = UpdateExpression(
          source: f.source,
          start: 0,
          end: f.source.length,
          operand: target,
          op: op,
          isPrefix: prefix,
        );
        checkTree(root);
        expect(root.isPrefix, prefix);
        expect(walk(root), [root, target, receiver, target.property]);
      }
    },
  );

  test('preserves super as the explicit receiver of an indexed assignment', () {
    final f = SyntaxFixture('super[key()] >>>= value()');
    final receiver = SuperExpression(source: f.source, start: 0, end: 5);
    final target = IndexExpression(
      source: f.source,
      start: 0,
      end: f.at(']') + 1,
      target: receiver,
      index: f.emptyCall('key'),
    );
    final root = AssignmentExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      left: target,
      op: .unsignedShiftRight,
      right: f.emptyCall('value'),
    );
    checkTree(root);
    expect(root.op.spelling, '>>>=');
    expect(target.isNullAware, isFalse);
    expect(walk(root).whereType<SuperExpression>().single, same(receiver));
    expect(walk(root).whereType<InvocationExpression>().map((n) => n.text), [
      'key()',
      'value()',
    ]);
  });

  test('keeps nullable type syntax separate from cast and test operands', () {
    final f = SyntaxFixture('(value as Object?) is! String');
    final cast = CastExpression(
      source: f.source,
      start: 1,
      end: f.at(')'),
      expression: f.reference('value'),
      type: f.type('Object', nullable: true),
    );
    final root = TypeTestExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      expression: ParenthesizedExpression(
        source: f.source,
        start: 0,
        end: cast.end + 1,
        expression: cast,
      ),
      type: f.type('String'),
      isNegated: true,
    );
    checkTree(root);
    expect(root.isNegated, isTrue);
    expect(cast.type.isNullable, isTrue);
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'value',
      'Object',
      'String',
    ]);
  });

  test('retains a throw operand and zero-width recovery syntax', () {
    final f = SyntaxFixture('throw error');
    final root = ThrowExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      expression: f.reference('error'),
    );
    checkTree(root);
    expect(root.expression.text, 'error');
    final missing = MissingExpression(
      source: f.source,
      offset: f.source.length,
    );
    expect(missing.text, isEmpty);
    expect(missing.start, missing.end);
    expect(walk(missing), [missing]);
    expect(
      () => MissingExpression(source: f.source, offset: f.source.length + 1),
      throwsRangeError,
    );
  });

  test('preserves instantiation and invocation grouping', () {
    final f = SyntaxFixture('(f<int>)(value)');
    final instantiated = TypeInstantiationExpression(
      source: f.source,
      start: 1,
      end: f.at('>') + 1,
      expression: f.reference('f'),
      typeArguments: TypeArgumentList(
        source: f.source,
        start: f.at('<'),
        end: f.at('>') + 1,
        arguments: [f.type('int')],
      ),
    );
    final root = InvocationExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      callee: ParenthesizedExpression(
        source: f.source,
        start: 0,
        end: instantiated.end + 1,
        expression: instantiated,
      ),
      arguments: ArgumentList(
        source: f.source,
        start: f.at('(value'),
        end: f.source.length,
        arguments: [
          Argument(
            source: f.source,
            start: f.at('value'),
            end: f.at('value') + 5,
            value: f.reference('value'),
          ),
        ],
      ),
    );
    checkTree(root);
    expect(root.typeArguments, isNull);
    expect(root.callee.text, '(f<int>)');
    expect(instantiated.typeArguments.text, '<int>');
  });

  test('keeps parameterized constructor references unbound', () {
    final f = SyntaxFixture('C<int>.new');
    final applied = TypeInstantiationExpression(
      source: f.source,
      start: 0,
      end: 6,
      expression: f.reference('C'),
      typeArguments: TypeArgumentList(
        source: f.source,
        start: 1,
        end: 6,
        arguments: [f.type('int')],
      ),
    );
    final root = PropertyAccessExpression(
      source: f.source,
      start: 0,
      end: f.source.length,
      target: applied,
      property: f.id('new'),
    );
    checkTree(root);
    expect(root.target, same(applied));
    expect(walk(root).whereType<Identifier>().map((n) => n.text), [
      'C',
      'int',
      'new',
    ]);
  });

  test('rejects cross-snapshot operands and reordered types and indexes', () {
    final f = SyntaxFixture('a[b]');
    final other = SyntaxFixture('a[b]');
    expect(
      () => IndexExpression(
        source: f.source,
        start: 0,
        end: 4,
        target: f.reference('a'),
        index: other.reference('b'),
      ),
      throwsArgumentError,
    );
    expect(
      () => IndexExpression(
        source: f.source,
        start: 0,
        end: 4,
        target: f.reference('b'),
        index: f.reference('a'),
      ),
      throwsArgumentError,
    );
    expect(
      () => CastExpression(
        source: f.source,
        start: 0,
        end: 4,
        expression: f.reference('b'),
        type: f.type('a'),
      ),
      throwsArgumentError,
    );
  });
}
