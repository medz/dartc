import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dartc/sdk.dart';

import 'src/sdk_sources.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    throw ArgumentError('Usage: build_sources.dart [source-cache]');
  }
  final sdk = await SdkSources(
    Directory(arguments.singleOrNull ?? 'build/sources/sdk'),
  ).prepare();
  final files = <String, List<int>>{};
  for (final (prefix, directory) in [
    ('sdk', sdk),
    ('dartc/src/runtime', Directory('lib/src/runtime')),
  ]) {
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (file is Directory) continue;
      if (file is! File) {
        throw FormatException('Source resource is not a file: ${file.path}');
      }
      final name = file.uri.pathSegments
          .skip(directory.uri.pathSegments.length - 1)
          .join('/');
      files['$prefix/$name'] = file.readAsBytesSync();
    }
  }
  for (final path in ['layout/memory.dart', 'src/layout/memory_layout.dart']) {
    files['dartc/$path'] = File('lib/$path').readAsBytesSync();
  }
  final names = files.keys.toList()..sort();
  files['manifest.json'] = utf8.encode(
    jsonEncode({
      'format': 1,
      'files': {
        for (final name in names) name: sha256.convert(files[name]!).toString(),
      },
    }),
  );
  final archive = Archive();
  for (final name in ['manifest.json', ...names]) {
    archive.add(
      ArchiveFile.bytes(name, files[name]!)
        ..mode = 0x81a4
        ..lastModTime = 0
        ..lastModDosTime = 0x00210000,
    );
  }
  final bytes = ZipEncoder().encodeBytes(archive, level: 6);
  final sources = SourceArchive(bytes);
  DartSdk(sources);
  for (final name in sources.paths) {
    sources.read(name);
  }
  final output = File('lib/src/sdk/sources.zip');
  await output.writeAsBytes(bytes);
  stdout.writeln(
    'Packaged ${names.length} source files (${bytes.length} bytes).',
  );
}
