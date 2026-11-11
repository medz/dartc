import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/sdk.dart';

/// Builds and packages the compiler without generating Dart source files.
Future<void> buildCompiler(File destination) async {
  final resources = await File('lib/src/sdk/sources.zip').readAsBytes();
  final sources = SourceArchive(resources);
  DartSdk(sources);
  for (final name in sources.paths) {
    sources.read(name);
  }
  final digest = sha256.convert(resources).toString();
  await destination.parent.create(recursive: true);
  final work = await destination.parent.createTemp('.dartc-build-');
  try {
    final raw = File.fromUri(work.uri.resolve('unbundled'));
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      '-Ddartc.resources=$digest',
      'bin/dartc.dart',
      '-o',
      raw.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Cannot build dartc: ${result.stdout}${result.stderr}');
    }
    final output = await raw.copy(work.uri.resolve('dartc').toFilePath());
    await output.writeAsBytes(
      ExecutableResources(raw).embed(resources),
      flush: true,
    );
    if (sha256.convert(ExecutableResources(output).read()).toString() !=
        digest) {
      throw const FormatException(
        'Packaged resources differ from build inputs.',
      );
    }
    await output.rename(destination.path);
  } finally {
    await work.delete(recursive: true);
  }
}
