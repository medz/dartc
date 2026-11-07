import 'dart:io';

import 'package:dartc/artifact.dart';
import 'package:dartc/formats.dart';
import 'package:dartc/target.dart';

/// Links object artifacts with the host's `cc` or `ar` program.
///
/// This initial implementation requires the host and output target to match.
/// Object encoding remains in Dart; no assembly source or Dart SDK is invoked.
final class Linker(final Target target) {
  /// Builds a native library, preserving an existing output if linking fails.
  Future<void> link(
    Iterable<ObjectFile> input,
    File output,
    OutputKind kind,
  ) async {
    final objects = input.toList();
    if (kind == .object ||
        objects.isEmpty ||
        objects.any((o) => o.target != target)) {
      throw ArgumentError(
        'Expected matching objects and a library output kind.',
      );
    }
    if (target != Target.host()) {
      throw UnsupportedError('Native linking requires a $target host.');
    }
    await output.absolute.parent.create(recursive: true);
    final work = await output.absolute.parent.createTemp('.dartc-link-');
    try {
      final paths = <String>[];
      for (final (i, object) in objects.indexed) {
        final file = File.fromUri(work.uri.resolve('$i.o'));
        await file.writeAsBytes(switch (target.operatingSystem) {
          .macos => MachO.encode(object),
          .linux => Elf.encode(object),
        });
        paths.add(file.path);
      }
      final linked = File.fromUri(work.uri.resolve('output'));
      final program = kind == .staticLibrary ? 'ar' : 'cc';
      final args = kind == .staticLibrary
          ? ['rcs', linked.path, ...paths]
          : [
              if (target.operatingSystem == .macos) ...[
                '-arch',
                target.architecture == .arm64 ? 'arm64' : 'x86_64',
                '-dynamiclib',
                '-Xlinker',
                '-install_name',
                '-Xlinker',
                '@rpath/${output.uri.pathSegments.last}',
              ] else ...[
                '-shared',
                '-Wl,--no-undefined',
              ],
              ...paths,
              '-o',
              linked.path,
            ];
      final result = await Process.run(program, args);
      if (result.exitCode != 0) {
        throw ProcessException(
          program,
          args,
          '${result.stdout}${result.stderr}',
          result.exitCode,
        );
      }
      await linked.rename(output.absolute.path);
    } finally {
      await work.delete(recursive: true);
    }
  }
}
