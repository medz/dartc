import 'dart:io';

/// Standard library sources for the supported Dart SDK version.
final class DartSdk._(final Directory directory, final String version) {
  /// The standard library version currently checked by dartc.
  static const supportedVersion = '3.13.7';

  /// The official source revision used when no compatible SDK is installed.
  static const sourceRevision = '416e33b0ffaef062a60ec966bb8c82ed2b83f128';

  /// Checks required source files and the version without modifying the SDK.
  ///
  /// [path] can name an installed SDK or a prepared source-only SDK.
  /// Other versions throw [UnsupportedError]; this does not attest that a
  /// caller-supplied SDK's contents are identical to the official release.
  factory at(String path) {
    final root = Directory(Directory(path).absolute.resolveSymbolicLinksSync());
    for (final file in [
      'version',
      'lib/libraries.json',
      'lib/core/core.dart',
      'lib/_internal/allowed_experiments.json',
      'lib/_internal/sdk_library_metadata/lib/libraries.dart',
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
    if (version != supportedVersion) {
      throw UnsupportedError(
        'SDK $version is not supported; expected $supportedVersion: ${root.path}',
      );
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
