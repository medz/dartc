import 'dart:io';

/// An installed SDK with its original standard library sources.
final class DartSdk._(final Directory directory, final String version) {
  /// Validates an SDK root without copying or modifying its files.
  factory at(String path) {
    final root = Directory(path).absolute;
    for (final file in [
      'version',
      'lib/libraries.json',
      'lib/core/core.dart',
    ]) {
      if (!File.fromUri(root.uri.resolve(file)).existsSync()) {
        throw ArgumentError('Missing SDK file: ${root.path}/$file');
      }
    }
    final version = File.fromUri(root.uri.resolve('version'))
        .readAsStringSync()
        .trim();
    if (version.isEmpty) {
      throw FormatException('Empty SDK version: ${root.path}');
    }
    return ._(root, version);
  }

  /// Locates the SDK containing the executable running this process.
  ///
  /// Throws when running as a standalone executable outside an SDK.
  factory current() =>
      .at(File(Platform.resolvedExecutable).parent.parent.path);

  /// The directory containing `dart:` library sources.
  Directory get libraries => Directory.fromUri(directory.uri.resolve('lib/'));
}
