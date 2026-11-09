import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cache.dart';
import 'sdk.dart';

/// Selects compatible installed sources or prepares the pinned source cache.
final class SdkResolver({Directory? cacheDirectory}) {
  final Directory? _cacheDirectory = cacheDirectory;

  /// The parent directory of revision-specific source caches.
  ///
  /// Defaults to `XDG_CACHE_HOME/dartc/sdk`, or the platform's user cache
  /// directory when that environment variable is absent.
  Directory get cacheDirectory {
    if (_cacheDirectory case final directory?) return directory.absolute;
    final environment = Platform.environment;
    final xdg = environment['XDG_CACHE_HOME'];
    if (xdg != null && xdg.isNotEmpty && Directory(xdg).isAbsolute) {
      return Directory.fromUri(Directory(xdg).uri.resolve('dartc/sdk/'));
    }
    final cacheBase = environment[Platform.isWindows ? 'LOCALAPPDATA' : 'HOME'];
    if (cacheBase == null || cacheBase.isEmpty) {
      throw FileSystemException('Cannot locate the user cache directory.');
    }
    final suffix = Platform.isMacOS
        ? 'Library/Caches/dartc/sdk/'
        : Platform.isWindows
        ? 'dartc/sdk/'
        : '.cache/dartc/sdk/';
    return Directory.fromUri(Directory(cacheBase).uri.resolve(suffix));
  }

  /// Resolves [source], or checks the current SDK, PATH, then the source cache.
  ///
  /// An explicit source is an SDK root, Dart executable path, or command on
  /// PATH. It never falls back on failure. Dart command wrappers are queried
  /// with a temporary program; no shell interprets [source].
  Future<DartSdk> resolve({String? source}) async {
    if (source != null) {
      if (source.isEmpty) throw ArgumentError.value(source, 'source');
      if (Directory(source).existsSync()) return DartSdk.at(source);
      if (source.contains('/') || source.contains('\\')) {
        return _executable(source);
      }
      for (final file in _commands(source)) {
        if (file.existsSync()) return _executable(file.path);
      }
      throw ArgumentError('Dart SDK command not found: $source');
    }
    try {
      return DartSdk.current();
    } catch (error) {
      if (!_unavailable(error)) rethrow;
    }
    for (final file in _commands(Platform.isWindows ? 'dart.exe' : 'dart')) {
      if (!file.existsSync()) continue;
      try {
        return await _executable(file.path);
      } catch (error) {
        if (!_unavailable(error)) rethrow;
      }
    }
    return resolveCached();
  }

  /// Prepares the pinned official sources, including for later offline use.
  ///
  /// Reuses only a complete cache with matching contents. A corrupt cache
  /// fails without being replaced; remove it explicitly before downloading
  /// again. No SDK executable is downloaded or used from the cache.
  Future<DartSdk> resolveCached() => SourceCache(cacheDirectory).resolve();

  Iterable<File> _commands(String name) sync* {
    for (final path in (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    )) {
      yield File.fromUri(
        Directory(path.isEmpty ? '.' : path).absolute.uri
            .resolveUri(Uri(pathSegments: [name])),
      );
    }
  }

  bool _unavailable(Object error) =>
      error is ArgumentError ||
      error is FormatException ||
      error is UnsupportedError ||
      error is IOException;

  Future<DartSdk> _executable(String path) async {
    final executable = File(File(path).resolveSymbolicLinksSync());
    try {
      return DartSdk.at(executable.parent.parent.path);
    } on ArgumentError {
      // Command wrappers need to report the SDK they actually launch.
    }
    final work = await Directory.systemTemp.createTemp('dartc-sdk-');
    Process? process;
    try {
      final probe = File.fromUri(work.uri.resolve('sdk.dart'));
      await probe.writeAsString(
        "import 'dart:convert'; import 'dart:io'; void main() { stdout.write(jsonEncode(Platform.resolvedExecutable)); }",
      );
      process = await Process.start(executable.path, [probe.path]);
      final (status, output, errors) = await (
        process.exitCode,
        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
      ).wait.timeout(const Duration(seconds: 30));
      if (status != 0) {
        throw ArgumentError('Cannot query Dart SDK through $path: $errors');
      }
      if (jsonDecode(output) case final String resolved
          when resolved.isNotEmpty) {
        return DartSdk.at(File(resolved).parent.parent.path);
      }
      throw FormatException('Invalid SDK location from $path.');
    } on TimeoutException {
      throw ArgumentError('Timed out querying Dart SDK through $path.');
    } finally {
      process?.kill();
      await work.delete(recursive: true);
    }
  }
}
