import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// An immutable, indexed ZIP of source files with checked content digests.
///
/// Construction reads metadata only. [read] decompresses and verifies one file;
/// expanded source contents are not retained by this archive.
/// A supplied archive checksum validates compressed input before indexing.
/// Archives may contain up to 8192 files, 32 MiB compressed, 64 MiB expanded,
/// and 8 MiB per file. Invalid archives throw [FormatException].
final class SourceArchive(Uint8List bytes, {String? digest}) {
  final _files = <String, (ZipFileHeader, String)>{};

  this {
    if (bytes.length > 32 << 20) {
      throw const FormatException('Source archive exceeds 32 MiB.');
    }
    if (digest != null && sha256.convert(bytes).toString() != digest) {
      throw const FormatException('Source archive digest mismatch.');
    }
    try {
      final input = InputMemoryStream(Uint8List.fromList(bytes));
      final directory = ZipDirectory();
      final entries = <String, ZipFileHeader>{};
      var size = 0;
      for (final entry in directory.headers(input, verify: true)) {
        final name = entry.filename;
        final type = (entry.externalFileAttributes >> 16) & 0xf000;
        size += entry.uncompressedSize;
        if (entries.length >= 8192 ||
            size > 64 << 20 ||
            entry.uncompressedSize < 0 ||
            entry.compressedSize < 0 ||
            entry.uncompressedSize > 8 << 20 ||
            !{0, 8}.contains(entry.compressionMethod) ||
            entry.generalPurposeBitFlag & 1 != 0 ||
            !{0, 0x8000}.contains(type) ||
            entry.externalFileAttributes & 0x10 != 0 ||
            name.contains(RegExp(r'[\\:\x00]')) ||
            name
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..') ||
            entries.containsKey(name)) {
          throw FormatException('Invalid source archive entry: $name');
        }
        entries[name] = entry;
      }
      if (directory.filePosition < 0 ||
          directory.numberOfThisDisk != 0 ||
          directory.diskWithTheStartOfTheCentralDirectory != 0 ||
          directory.totalCentralDirectoryEntries != entries.length) {
        throw const FormatException('Invalid source archive directory.');
      }
      final manifest = entries.remove('manifest.json');
      if (manifest == null) {
        throw const FormatException('Missing source manifest.');
      }
      final Object? decoded = jsonDecode(utf8.decode(_read(manifest)));
      if (decoded case {'format': 1, 'files': final Map<String, dynamic> hashes}
          when hashes.length == entries.length) {
        for (final MapEntry(:key, :value) in entries.entries) {
          final hash = hashes[key];
          if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
            throw FormatException('Invalid source digest: $key');
          }
          for (
            var slash = key.indexOf('/');
            slash >= 0;
            slash = key.indexOf('/', slash + 1)
          ) {
            if (entries.containsKey(key.substring(0, slash))) {
              throw FormatException('Source file is also a directory: $key');
            }
          }
          _files[key] = (value, hash);
        }
      } else {
        throw const FormatException('Invalid source manifest.');
      }
    } on ArchiveException catch (error) {
      throw FormatException('Invalid source archive: $error');
    }
  }

  /// File paths relative to the archive root, using `/` separators.
  Iterable<String> get paths => _files.keys;

  /// Whether [path] names a source file.
  bool contains(String path) => _files.containsKey(path);

  /// The uncompressed byte length, or `null` for a missing file.
  int? length(String path) => _files[path]?.$1.uncompressedSize;

  /// Reads and checks [path], throwing [FormatException] if absent or damaged.
  Uint8List read(String path) {
    final entry = _files[path];
    if (entry == null) throw FormatException('Missing source file: $path');
    try {
      final bytes = _read(entry.$1);
      if (sha256.convert(bytes).toString() != entry.$2) {
        throw FormatException('Source digest mismatch: $path');
      }
      return bytes.asUnmodifiableView();
    } on ArchiveException catch (error) {
      throw FormatException('Invalid source file $path: $error');
    }
  }

  /// The SHA-256 of sorted paths and declared digests beneath [prefix].
  ///
  /// Paths in this digest are relative to [prefix]. File contents are checked
  /// against their declared digests when read.
  String fingerprint(String prefix) {
    final records = [
      for (final MapEntry(:key, :value) in _files.entries)
        if (key.startsWith(prefix))
          '${key.substring(prefix.length)}\u0000${value.$2}\n',
    ]..sort();
    return sha256.convert(utf8.encode(records.join())).toString();
  }

  Uint8List _read(ZipFileHeader header) {
    final file = header.file!..throwOnError = true;
    final bytes = file.getStream().toUint8List();
    if (bytes.length != header.uncompressedSize ||
        getCrc32(bytes) != header.crc32) {
      throw FormatException('Invalid source size or CRC: ${header.filename}');
    }
    return bytes;
  }
}
