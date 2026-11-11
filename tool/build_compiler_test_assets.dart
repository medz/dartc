import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

import '../test/support/native_assets.dart';
import 'src/compiler_build.dart';

Future<void> main() async {
  final directory = Directory('build/test/sdk')..createSync(recursive: true);
  final archive = Archive();
  final sources = (await DartSdk.load()).sources;
  for (final path in sources.paths.where((path) => path.startsWith('sdk/'))) {
    final name = path.substring(4);
    if (name == 'version' || name == 'revision') continue;
    archive.add(
      ArchiveFile.bytes(
        'sdk-${DartSdk.sourceRevision}/${name == 'LICENSE' ? name : 'sdk/$name'}',
        sources.read(path),
      )..lastModTime = 0,
    );
  }
  await File.fromUri(directory.uri.resolve('source.tar.gz'))
      .writeAsBytes(gzip.encode(TarEncoder().encode(archive)));

  final input = Directory('build/test/compiler/input');
  await input.create(recursive: true);
  for (final file in [
    File('lib/interop.dart'),
    ...Directory('lib/src/interop').listSync(recursive: true).whereType<File>(),
  ]) {
    final copy = File.fromUri(input.uri.resolve('dependency/${file.path}'));
    await copy.parent.create(recursive: true);
    await file.copy(copy.path);
  }
  await File('test/compiler/fixtures/arithmetic.dart')
      .copy('${input.path}/entry.dart');
  await File('test/compiler/fixtures/standalone_program.dart')
      .copy('${input.path}/program.dart');
  final config = File('${input.path}/.dart_tool/package_config.json');
  await config.parent.create(recursive: true);
  await File('test/compiler/fixtures/standalone_packages.json')
      .copy(config.path);

  final assets = NativeAssets(Target.host());
  await buildCompiler(assets.file('compiler/dartc'));
  for (final (source, name) in [
    ('test/compiler/fixtures/standalone_client.dart', 'client'),
  ]) {
    final output = assets.file('compiler/$name');
    await output.parent.create(recursive: true);
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      source,
      '-o',
      output.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Cannot build $source: ${result.stdout}${result.stderr}',
      );
    }
  }
  stdout.writeln('Prepared compiler test assets for ${Target.host()}.');
}
