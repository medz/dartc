import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'unicode_case_data.dart';

/// Source files used to compile the standard library and target runtime.
abstract class SdkSources() {
  /// Reads the source tree distributed with the dartc package.
  ///
  /// Native AOT hosts supply sources explicitly when package resolution is
  /// unavailable. No installed SDK is discovered or downloaded.
  static Future<SdkSources> load() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartc/sdk.dart'),
    );
    if (uri == null || uri.scheme != 'file') {
      throw const FormatException(
        'SDK sources are unavailable; provide SdkSources.',
      );
    }
    return SourceDirectory(Directory.fromUri(uri.resolve('../')));
  }

  /// File paths relative to the dartc package root, using `/` separators.
  Iterable<String> get paths;

  /// Whether [path] names a source file.
  bool contains(String path);

  /// The byte length, or `null` for a missing file.
  int? length(String path);

  /// Reads [path], throwing [FormatException] if absent or invalid.
  Uint8List read(String path);

  /// The SHA-256 of sorted relative paths and content digests under [prefix].
  String fingerprint(String prefix) {
    final records = [
      for (final path in paths)
        if (path.startsWith(prefix))
          '${path.substring(prefix.length)}\u0000${sha256.convert(read(path))}\n',
    ]..sort();
    return sha256.convert(utf8.encode(records.join())).toString();
  }
}

/// Reads SDK files, shared contracts and derived Unicode case constants.
///
/// File contents are read on every request. Symbolic links are rejected so that
/// resource packaging cannot include files outside the source tree.
/// Unicode generation inputs stay private; the source view exposes their
/// derived Dart constants and license for independent archive execution.
final class SourceDirectory(Directory directory) extends SdkSources {
  final Directory directory = directory.absolute;

  this {
    if (FileSystemEntity.typeSync(this.directory.path, followLinks: false) !=
        .directory) {
      throw FormatException('Invalid source directory: ${this.directory.path}');
    }
  }

  static const _directories = ['sdk/std', 'sdk/runtime', 'sdk/patches'];
  static const _shared = [
    'lib/runtime/contracts.dart',
    'lib/layout/memory.dart',
    'lib/src/layout/memory_layout.dart',
  ];

  bool _isUnicodeInput(String path) =>
      unicodeCaseInputs.containsKey(path) &&
      path != 'sdk/patches/unicode/LICENSE';

  File? _file(String path) {
    final parts = path.split('/');
    if ((!_shared.contains(path) &&
            !_directories.any((root) => path.startsWith('$root/'))) ||
        path.contains(RegExp(r'[\\:\x00]')) ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return null;
    }
    for (var i = 1; i <= parts.length; i++) {
      final uri = directory.uri.resolveUri(Uri(pathSegments: parts.take(i)));
      if (FileSystemEntity.typeSync(uri.toFilePath(), followLinks: false) ==
          .link) {
        throw FormatException('Source resources cannot be links: $path');
      }
    }
    return File.fromUri(directory.uri.resolveUri(Uri(pathSegments: parts)));
  }

  @override
  Iterable<String> get paths sync* {
    if (contains(unicodeCaseSource)) {
      yield unicodeCaseSource;
    } else if (contains('sdk/patches/unicode_case.dart')) {
      throw const FormatException('Missing Unicode case generation inputs.');
    }
    for (final name in _shared) {
      if (!contains(name)) throw FormatException('Missing source file: $name');
      yield name;
    }
    for (final name in _directories) {
      final root = Directory.fromUri(directory.uri.resolve('$name/'));
      if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
          .directory) {
        throw FormatException('Invalid source directory: ${root.path}');
      }
      for (final entry in root.listSync(recursive: true, followLinks: false)) {
        if (entry is Directory) continue;
        if (entry is! File) {
          throw FormatException('Source resource is not a file: ${entry.path}');
        }
        final path = entry.uri.pathSegments
            .skip(directory.uri.pathSegments.length - 1)
            .join('/');
        if (!_isUnicodeInput(path)) yield path;
      }
    }
  }

  @override
  bool contains(String path) => path == unicodeCaseSource
      ? unicodeCaseInputs.keys.every(
          (input) => _file(input)?.existsSync() ?? false,
        )
      : !_isUnicodeInput(path) && (_file(path)?.existsSync() ?? false);

  @override
  int? length(String path) {
    if (_isUnicodeInput(path)) return null;
    if (path == unicodeCaseSource) {
      return contains(path) ? read(path).length : null;
    }
    final file = _file(path);
    return file != null && file.existsSync() ? file.lengthSync() : null;
  }

  @override
  Uint8List read(String path) {
    if (path == unicodeCaseSource) return unicodeCaseData(_readFile);
    if (_isUnicodeInput(path)) {
      throw FormatException('Missing source file: $path');
    }
    return _readFile(path);
  }

  Uint8List _readFile(String path) {
    final file = _file(path);
    if (file == null || !file.existsSync()) {
      throw FormatException('Missing source file: $path');
    }
    return file.readAsBytesSync().asUnmodifiableView();
  }
}
