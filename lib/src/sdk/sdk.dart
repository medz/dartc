import 'dart:convert';
import 'dart:io' show gzip;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'sources.g.dart';

/// The immutable official standard library sources bundled with this compiler.
final class const DartSdk() {
  /// The fixed standard library version.
  static const version = '3.13.7';

  /// The official commit containing the bundled source files.
  static const sourceRevision = '416e33b0ffaef062a60ec966bb8c82ed2b83f128';

  /// The SHA-256 of sorted file names and their original content digests.
  static const sourceFingerprint =
      'a054ede359302c352757ea57878e5e4033c6c955a9d4e2da3ec02c4087dc8b8e';

  /// Source text and metadata keyed by paths relative to the SDK root.
  ///
  /// Includes the original license, version and revision. Damaged or incomplete
  /// bundled contents throw [FormatException]; no external source is consulted.
  Map<String, String> get files => _files;

  static final _files = _read();

  static Map<String, String> _read() {
    final files = <String, String>{}, records = <String>[];
    try {
      final archive = TarDecoder().decodeBytes(
        gzip.decode(base64.decode(sdkArchive)),
        verify: true,
      );
      for (final file in archive) {
        if (!file.isFile ||
            file.isSymbolicLink ||
            file.isHardLink ||
            files.containsKey(file.name)) {
          throw const FormatException('Invalid bundled SDK entry.');
        }
        final bytes = file.content;
        records.add('${file.name}\u0000${sha256.convert(bytes)}\n');
        files[file.name] = utf8.decode(bytes);
      }
    } on ArchiveException catch (error) {
      throw FormatException('Invalid bundled SDK: $error');
    }
    records.sort();
    if (sha256.convert(utf8.encode(records.join())).toString() !=
        sourceFingerprint) {
      throw const FormatException(
        'Bundled SDK contents do not match the fixed source revision.',
      );
    }
    return Map.unmodifiable(files);
  }
}
