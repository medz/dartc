import 'package:dartc/project.dart';

Uri uri(String path) =>
    Uri.parse(path.startsWith('dart:') ? path : 'memory:/app/$path');

ProjectLoader loader(
  Map<Uri, String> files, {
  Map<String, String> environment = const {},
}) => ProjectLoader(readSource: (uri) => files[uri], environment: environment);

Map<Uri, String> sources(Map<String, String> files) => {
  uri('dart:core'): 'library dart.core;',
  for (final entry in files.entries) uri(entry.key): entry.value,
};
