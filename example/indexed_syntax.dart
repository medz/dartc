import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(
    Uri.parse('memory:example'),
    'int twice(int x) => x + x; int zero() => 0;',
  );
  final parsed = parseCompilationUnit(scan(source));
  final tree = parsed.tree;
  if (parsed.hasErrors) throw StateError('Invalid example');
  final firstDeclaration = tree.childAt(tree.root, 0);
  for (final id in tree.walk(firstDeclaration)) {
    print('${tree.kind(id).name} ${tree.start(id)}..${tree.end(id)}');
  }

  // #region build
  final input = SourceFile(Uri.parse('memory:sum'), 'a + b');
  final builder = SyntaxTreeBuilder(input);
  final left = builder.identifierExpression(
    builder.identifier(start: 0, end: 1),
  );
  final right = builder.identifierExpression(
    builder.identifier(start: 4, end: 5),
  );
  final root = builder.binaryExpression(left: left, op: .add, right: right);
  final sum = builder.finish(root).view<BinaryExpression>(root);
  print(sum.text); // a + b
  // #endregion build
}
