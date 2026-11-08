import 'package:dartc/compiler.dart';
import 'package:dartc/artifact.dart';

import 'dart:io';

import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/native_assets.dart';

Future<void> main() async {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final assets = NativeAssets(target);
      await assets.directory.create(recursive: true);
      final arithmetic = await Compiler(target)
          .compile(['test/compiler/fixtures/arithmetic.dart']);
      await arithmetic.write(
        assets.file('compiler/arithmetic.o'),
        header: assets.file('compiler/arithmetic.h'),
      );
      await arithmetic.write(
        assets.file('compiler/arithmetic.a'),
        kind: .staticLibrary,
      );
      await arithmetic.write(
        assets.library('compiler/arithmetic'),
        kind: .sharedLibrary,
      );

      final ImageFormat format = switch (os) {
        .macos => MachO(target),
        .linux => Elf(target),
      };
      final linker = Linker(format);
      Future<void> shared(List<ObjectModule> modules, File output) =>
          output.writeAsBytes(
            format.encodeImage(
              linker.link(modules, libraryName: output.uri.pathSegments.last),
            ),
          );
      await shared([aliases(target)], assets.library('codegen/aliases'));
      final inputs = [
        functions(target, {'first': 40}),
        functions(target, {'second': 2}),
      ];
      await assets
          .file('linker/values.a')
          .writeAsBytes(ArchiveWriter(format).encode(inputs));
      await shared(inputs, assets.library('linker/values'));
      for (final (i, object) in inputs.indexed) {
        await assets
            .file('linker/$i.o')
            .writeAsBytes(format.encodeObject(object));
      }
      await shared([
        functions(target, symbolValues),
      ], assets.library('linker/symbols'));
      print('Built test assets for $target.');
    }
  }
}
