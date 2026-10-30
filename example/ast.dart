import 'package:dartc/ast.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(Uri.parse('memory:example.dart'), 'List<int>');
  final tree = NamedTypeAnnotation(
    source: source,
    start: 0,
    end: source.length,
    name: Identifier(source: source, start: 0, end: 4),
    typeArguments: TypeArgumentList(
      source: source,
      start: 4,
      end: 9,
      arguments: [
        NamedTypeAnnotation(
          source: source,
          start: 5,
          end: 8,
          name: Identifier(source: source, start: 5, end: 8),
        ),
      ],
    ),
  );

  for (final node in walk(tree)) {
    if (node is NamedTypeAnnotation) {
      print('${node.name.text}: ${node.start}..${node.end}');
    }
  }
}
