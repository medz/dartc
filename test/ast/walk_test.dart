import 'package:dartc/ast.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('walk is repeatable and has independent lazy iterators', () {
    final root = functionTypeFixture();
    final nodes = walk(root);
    final expected = nodes.toList();
    expect(nodes, expected);
    expect(nodes.first, same(root));
    final first = nodes.iterator;
    final second = nodes.iterator;
    for (final node in expected) {
      expect(first.moveNext(), isTrue);
      expect(first.current, same(node));
    }
    expect(first.moveNext(), isFalse);
    expect(first.moveNext(), isFalse);
    expect(second.moveNext(), isTrue);
    expect(second.current, same(root));
    expect(nodes.take(2), expected.take(2));
  });

  test('walk handles deep unary nesting without recursion', () {
    const depth = 100000;
    final source = SourceFile(
      Uri.parse('memory:deep.dart'),
      '${'(' * depth}0${')' * depth}',
    );
    Expression node = LiteralExpression(
      source: source,
      start: depth,
      end: depth + 1,
      kind: .integer,
    );
    for (var i = depth - 1; i >= 0; i--) {
      node = ParenthesizedExpression(
        source: source,
        start: i,
        end: source.length - i,
        expression: node,
      );
    }
    var count = 0;
    for (final current in walk(node)) {
      expect(current.start, count);
      count++;
    }
    expect(count, depth + 1);
  });

  test('walk preserves a wide argument list without reversing siblings', () {
    const width = 100000;
    final source = SourceFile(Uri.parse('memory:wide.dart'), '0,' * width);
    final arguments = [
      for (var i = 0; i < width; i++)
        Argument(
          source: source,
          start: i * 2,
          end: i * 2 + 1,
          value: LiteralExpression(
            source: source,
            start: i * 2,
            end: i * 2 + 1,
            kind: .integer,
          ),
        ),
    ];
    final root = ArgumentList(
      source: source,
      start: 0,
      end: source.length,
      arguments: arguments,
    );
    final iterator = walk(root).iterator;
    expect(iterator.moveNext(), isTrue);
    expect(iterator.current, same(root));
    for (final argument in arguments) {
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, same(argument));
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, same(argument.value));
    }
    expect(iterator.moveNext(), isFalse);
  });

  test('walk resumes pending branches after deeply nested left operands', () {
    const depth = 50000;
    final source = SourceFile(
      Uri.parse('memory:branches.dart'),
      '0+' * depth + '0',
    );
    final first = LiteralExpression(
      source: source,
      start: 0,
      end: 1,
      kind: .integer,
    );
    Expression root = first;
    for (var i = 1; i <= depth; i++) {
      root = BinaryExpression(
        source: source,
        start: 0,
        end: i * 2 + 1,
        left: root,
        op: .add,
        right: LiteralExpression(
          source: source,
          start: i * 2,
          end: i * 2 + 1,
          kind: .integer,
        ),
      );
    }
    final iterator = walk(root).iterator;
    for (var i = depth; i > 0; i--) {
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, isA<BinaryExpression>());
      expect(iterator.current.end, i * 2 + 1);
    }
    for (var i = 0; i <= depth; i++) {
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, isA<LiteralExpression>());
      expect(iterator.current.start, i * 2);
    }
    expect(iterator.moveNext(), isFalse);
  });

  test(
    'walk preserves shared zero-width recovery nodes at each occurrence',
    () {
      final source = SourceFile(Uri.parse('memory:missing.dart'), '');
      final missing = MissingTypeAnnotation(source: source, offset: 0);
      final root = TypeArgumentList(
        source: source,
        start: 0,
        end: 0,
        arguments: [missing, missing],
      );
      expect(walk(root), [root, missing, missing]);
    },
  );
}
