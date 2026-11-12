import 'dart:io';

import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../test/support/native_assets.dart';
import 'src/compiler_build.dart';

Future<void> main() async {
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
  await assets
      .file('compiler/sources.zip')
      .writeAsBytes(ExecutableResources(assets.file('compiler/dartc')).read());
  for (final (source, name) in [
    ('test/compiler/fixtures/standalone_client.dart', 'client'),
    ('test/compiler/fixtures/compiler_client.dart', 'compiler-client'),
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
