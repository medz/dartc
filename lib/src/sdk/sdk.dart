import 'dart:convert';

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
  static const version = '3.14.0';

  /// The official commit containing the bundled source files.
  static const sourceRevision = 'fa8c1270c374c1346931583a17c3b7f278d3822d';

  /// The SHA-256 of sorted file names and their original content digests.
  static const sourceFingerprint =
      '8ad9594aa0ffc4f7e0ea85f1877db1f4cab76aeecacf868e7afbcd6c90f95f28';

  /// Loads the fixed sources shipped in this Dart package.
  ///
  /// AOT library consumers can instead pass their own [SourceArchive] to
  /// [DartSdk.new]. Missing or corrupt resources fail without SDK discovery.
  static Future<DartSdk> load() async => DartSdk(await SourceArchive.load());
}
