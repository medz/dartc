import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(
    Uri.parse('memory:example'),
    'int twice(int x) => x + x;',
  );
  final parsed = parseCompilationUnit(scan(source));
  final tree = parsed.tree;
  if (parsed.hasErrors) throw StateError('Invalid example');
  for (final id in tree.walk()) {
    print('${tree.kind(id).name} ${tree.start(id)}..${tree.end(id)}');
  }
}
