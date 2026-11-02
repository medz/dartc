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
}
