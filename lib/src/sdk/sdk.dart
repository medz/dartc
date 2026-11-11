import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'source_archive.dart';

/// The fixed official SDK libraries within a source archive.
final class DartSdk(final SourceArchive sources) {
  this {
    if (sources.fingerprint('sdk/') != sourceFingerprint ||
        utf8.decode(sources.read('sdk/version')).trim() != version ||
        utf8.decode(sources.read('sdk/revision')).trim() != sourceRevision) {
      throw const FormatException(
        'SDK sources do not match the fixed revision.',
      );
    }
  }

  /// The fixed standard library version.
  static const version = '3.13.7';

  /// The official commit containing the bundled source files.
  static const sourceRevision = '416e33b0ffaef062a60ec966bb8c82ed2b83f128';

  /// The SHA-256 of sorted file names and their original content digests.
  static const sourceFingerprint =
      'a054ede359302c352757ea57878e5e4033c6c955a9d4e2da3ec02c4087dc8b8e';

  /// Loads the fixed sources shipped in this Dart package.
  ///
  /// AOT library consumers can instead pass their own [SourceArchive] to
  /// [DartSdk.new]. Missing or corrupt resources fail without SDK discovery.
  static Future<DartSdk> load() => _bundled;

  static final _bundled = _load();

  static Future<DartSdk> _load() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartc/src/sdk/sources.zip'),
    );
    if (uri == null || uri.scheme != 'file') {
      throw const FormatException(
        'Source resources are unavailable. Package the executable or provide DartSdk sources.',
      );
    }
    return DartSdk(SourceArchive(await File.fromUri(uri).readAsBytes()));
  }
}
