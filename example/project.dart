import 'package:dartc/project.dart';

Future<void> main() async {
  final entry = Uri.parse('memory:/main.dart');
  final value = entry.resolve('value.dart');
  final sources = {
    entry: "import 'value.dart'; void main() {}",
    value: 'const value = 42;',
    Uri.parse('dart:core'): 'library dart.core;',
  };
  final loader = ProjectLoader(readSource: (uri) => sources[uri]);
  final project = await loader.load(entry);
  for (final library in project.libraries.values) {
    print('${library.uri}: ${library.unit.node.members.length} members');
  }
  sources[value] = 'const value = 43;';
  final updated = await loader.update(project, changedSources: [value]);
  final tree = updated.libraries[value]!.unit.tree;
  final declaration = tree.childAt(tree.root, 0);
  print(tree.view(declaration).text); // const value = 43;
}
