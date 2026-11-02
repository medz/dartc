import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('assigns each colon to its conditional across calls and indexes', () {
    for (final (text, expected) in [
      (
        'a?[i] + f(x)?[j] : first : second',
        '(?: a (?: (+ (list i) (call f x)) (list j) first) second)',
      ),
      ('a[i]?[j](v)?[k]:c', '(?: (call (?[] ([] a i) j) v) (list k) c)'),
      ('a?[i]?[j].p?[k]:c', '(?: (. (?[] (?[] a i) j) p) (list k) c)'),
    ]) {
      expect(shape(parsed(text)), expected, reason: text);
    }
    final chain = '${'a?[i] + ' * 2000}f(x)?[j]:first:second';
    final branches = walk(parsed(chain)).whereType<ConditionalExpression>();
    expect(branches.map((branch) => branch.elseExpression.text), [
      'second',
      'first',
    ]);
  });

  test('preserves selectors after an ambiguous index chain', () {
    for (final suffix in [
      '.x',
      '?.x',
      '(a, name: b)',
      '[j]',
      '!',
      '<T>',
      '<T>(a)',
      '.x<T>(a)[j]!',
    ]) {
      final text = 'a?[i]?[j]?[k]$suffix : c';
      final node = parsed(text) as ConditionalExpression;
      expect(node.text, text);
      expect(node.condition.text, 'a');
      expect(node.elseExpression.text, 'c');
      expect(node.thenExpression.text, '[i]?[j]?[k]$suffix');
      expect(
        walk(node.thenExpression)
            .whereType<IndexExpression>()
            .where((node) => node.isNullAware)
            .length,
        2,
      );
    }
  });

  test('handles long index chains ending in mixed selectors', () {
    const count = 12001;
    const suffix = '.method<T>(x, name: y)[j]!';
    final text = 'a${'?[i]' * count}$suffix:c';
    final node = parsed(text) as ConditionalExpression;
    expect(node.text, text);
    expect(node.thenExpression, isA<NullAssertionExpression>());
    expect(
      walk(node.thenExpression).whereType<IndexExpression>().length,
      count,
    );
    final invocation = walk(node.thenExpression)
        .whereType<InvocationExpression>()
        .single;
    expect(invocation.arguments.text, '(x, name: y)');
    expect(invocation.typeArguments!.text, '<T>');
  });
}
