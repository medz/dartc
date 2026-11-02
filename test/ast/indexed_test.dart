import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  test('indices and typed views agree within their source snapshot', () {
    final source = SourceFile(Uri.parse('memory:expr'), 'a+b');
    final input = scan(source);
    final tree = parseExpression(input).tree;
    final root = tree.root;
    final left = tree.childAt(root, 0);
    expect(tree.kind(root), SyntaxKind.binaryExpression);
    final right = tree.childAt(root, 1);
    expect(tree.walk(), [
      root,
      left,
      tree.childAt(left, 0),
      right,
      tree.childAt(right, 0),
    ]);
    expect(tree.source, same(source));
    final cursor = tree.cursor();
    expect(() => cursor.current, throwsStateError);
    for (final id in tree.walk()) {
      expect(cursor.moveNext(), isTrue);
      expect(cursor.current, id);
      expect(cursor.view, equals(tree.view(id)));
      expect(cursor.kind, tree.kind(id));
      expect(cursor.childCount, tree.childCount(id));
      expect([cursor.start, cursor.end], [tree.start(id), tree.end(id)]);
    }
    expect(cursor.moveNext(), isFalse);
    expect(cursor.moveNext(), isFalse);
    final expr = tree.view(root) as BinaryExpression;
    expect(tree.indexOf(expr.left), left);
    expect(tree.view(left), equals(expr.left));
    expect([tree.start(left), tree.end(left)], [0, 1]);
    expect(() => tree.childAt(root, 2), throwsRangeError);
    expect(() => tree.view(-1), throwsRangeError);
    expect(
      () => parseExpression(input).tree.indexOf(expr),
      throwsArgumentError,
    );
  });

  test(
    'typed argument lists and binary operands refer to their child rows',
    () {
      final parsed = parseExpression(
        scan(SourceFile(Uri.parse('memory:call'), 'f(a + b, g())')),
      );
      final tree = parsed.tree;
      final args = (parsed.node as InvocationExpression).arguments;
      final list = tree.indexOf(args);
      expect(args.arguments.map(tree.indexOf), [
        tree.childAt(list, 0),
        tree.childAt(list, 1),
      ]);
      final sum = args.arguments.first.value as BinaryExpression;
      expect(sum.op, BinaryOperator.add);
      expect(tree.indexOf(sum.right), tree.childAt(tree.indexOf(sum), 1));
      final nested = args.arguments.last.value as InvocationExpression;
      expect(nested.arguments.arguments, isEmpty);
      expect(args.arguments.clear, throwsUnsupportedError);
    },
  );
}
