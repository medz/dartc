import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

import '../test/support/native_assets.dart';

Future<void> main() async {
  final directory = Directory('build/test/sdk')..createSync(recursive: true);
  final sdk = await SdkResolver(
    cacheDirectory: Directory.fromUri(directory.uri.resolve('cache/')),
  ).resolveCached();
  final archive = Archive();
  final files =
      sdk.directory.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments
        .skip(sdk.directory.uri.pathSegments.length - 1)
        .join('/');
    if (name == 'version' || name == 'revision') continue;
    final path =
        'sdk-${DartSdk.sourceRevision}/${name == 'LICENSE' ? name : 'sdk/$name'}';
    archive.add(
      ArchiveFile(path, file.lengthSync(), file.readAsBytesSync())
        ..lastModTime = 0,
    );
  }
  await File.fromUri(directory.uri.resolve('source.tar.gz'))
      .writeAsBytes(gzip.encode(TarEncoder().encode(archive)));
  stdout.writeln('Prepared SDK source test archive.');
  final probe = NativeAssets(Target.host()).file('sdk/resolve');
  await probe.parent.create(recursive: true);
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'test/sdk/fixtures/resolve.dart',
    '-o',
    probe.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Cannot build SDK test probe: ${result.stderr}');
  }
  stdout.writeln('Built SDK resolution test probe for ${Target.host()}.');
}
