import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:dartc/sdk.dart';

/// Prepares the pinned official inputs when building dartc.
final class SdkSources(final Directory directory) {
  static final _uri = Uri.https(
    'codeload.github.com',
    '/dart-lang/sdk/tar.gz/${DartSdk.sourceRevision}',
  );

  Future<Directory> prepare() async {
    final destination = Directory.fromUri(
      directory.absolute.uri.resolve(DartSdk.sourceRevision),
    );
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        .notFound) {
      return _verified(destination);
    }
    await directory.create(recursive: true);
    final work = await directory.createTemp('.${DartSdk.sourceRevision}-');
    try {
      final compressed = File.fromUri(work.uri.resolve('source.tar.gz'));
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(_uri);
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'SDK source download returned HTTP ${response.statusCode}.',
            uri: _uri,
          );
        }
        await _write(
          response.timeout(const Duration(seconds: 30)),
          compressed,
          64 << 20,
        );
      } on TimeoutException {
        throw HttpException('SDK source download timed out.', uri: _uri);
      } finally {
        client.close(force: true);
      }
      final tar = File.fromUri(work.uri.resolve('source.tar'));
      await _write(
        compressed.openRead().transform(gzip.decoder),
        tar,
        512 << 20,
      );
      final sdk = Directory.fromUri(work.uri.resolve('sdk/'));
      await sdk.create();
      _extract(tar, sdk);
      await File.fromUri(sdk.uri.resolve('version'))
          .writeAsString('${DartSdk.version}\n');
      await File.fromUri(sdk.uri.resolve('revision'))
          .writeAsString('${DartSdk.sourceRevision}\n');
      _verified(sdk);
      try {
        await sdk.rename(destination.path);
      } on FileSystemException {
        if (!await destination.exists()) rethrow;
        return _verified(destination);
      }
      return destination;
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> _write(Stream<List<int>> source, File file, int limit) async {
    final output = await file.open(mode: .write);
    var size = 0;
    try {
      await for (final bytes in source) {
        size += bytes.length;
        if (size > limit) {
          throw FormatException('SDK source archive exceeds $limit bytes.');
        }
        await output.writeFrom(bytes);
      }
    } finally {
      await output.close();
    }
  }

  void _extract(File tar, Directory sdk) {
    final input = InputFileStream(tar.path);
    final names = <String>{};
    var size = 0;
    const prefix = 'sdk-${DartSdk.sourceRevision}/';
    try {
      TarDecoder().decodeStream(
        input,
        verify: true,
        keepEntries: false,
        callback: (entry) {
          final String name;
          if (entry.name == '${prefix}LICENSE') {
            name = 'LICENSE';
          } else if (entry.name.startsWith('${prefix}sdk/lib/')) {
            name = entry.name.substring('${prefix}sdk/'.length);
          } else {
            return;
          }
          if (entry.isSymbolicLink ||
              entry.isHardLink ||
              name.contains('\\') ||
              name.contains('\u0000') ||
              name.split('/').any((part) => part == '..' || part == '.')) {
            throw FormatException('Invalid SDK archive path: ${entry.name}');
          }
          if (entry.isDirectory) return;
          size += entry.size;
          if (size > 32 << 20) {
            throw FormatException('SDK sources exceed 32 MiB.');
          }
          if (!names.add(name)) {
            throw FormatException('Duplicate SDK archive file: $name');
          }
          final output = File.fromUri(
            sdk.uri.resolveUri(Uri(pathSegments: name.split('/'))),
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(entry.content);
        },
      );
    } on ArchiveException catch (error) {
      throw FormatException('Invalid SDK source archive: $error');
    } finally {
      input.closeSync();
    }
  }

  Directory _verified(Directory directory) {
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
        .directory) {
      throw FormatException('Invalid SDK cache directory: ${directory.path}');
    }
    final records = <String>[];
    for (final entry in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Directory) continue;
      if (entry is! File) {
        throw FormatException('SDK cache contains a link: ${entry.path}');
      }
      final name = entry.uri.pathSegments
          .skip(directory.uri.pathSegments.length - 1)
          .join('/');
      records.add('$name\u0000${sha256.convert(entry.readAsBytesSync())}\n');
    }
    records.sort();
    if (sha256.convert(utf8.encode(records.join())).toString() !=
        DartSdk.sourceFingerprint) {
      throw FormatException(
        'SDK cache contents do not match ${DartSdk.sourceRevision}: ${directory.path}',
      );
    }
    return directory;
  }
}
