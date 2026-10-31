import 'package:dartc/project.dart';

Future<void> main() async {
  final entry = Uri.parse('memory:/main.dart');
  final sources = {
    entry: "import 'value.dart'; void main() {}",
    Uri.parse('memory:/value.dart'): 'const value = 42;',
    Uri.parse('dart:core'): 'library dart.core;',
  };
  final loader = ProjectLoader(readSource: (uri) => sources[uri]);
  final project = await loader.load(entry);
  for (final library in project.libraries.values) {
    print('${library.uri}: ${library.unit.node.members.length} members');
  }
  final reloaded = await loader.load(entry);
  print(
    identical(project.libraries[entry]!.unit, reloaded.libraries[entry]!.unit),
  ); // true
  loader.clear();
}
