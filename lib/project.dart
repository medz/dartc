/// Dart source loading, package resolution and immutable library graphs.
///
/// A loader reads source through a caller-supplied provider, selects language
/// versions and assembles parsed libraries and parts. Name binding, types and
/// constant evaluation belong to analysis.
///
/// {@example /example/project.dart}
library;

export 'src/project/load.dart' show ProjectLoader;
export 'src/project/project.dart';
export 'src/project/library.dart';
export 'src/project/packages/configuration.dart';
export 'src/project/packages/discovery.dart';
export 'src/project/resolve_uri.dart' show resolveSourceUri;
export 'src/project/sources/file_source.dart';
