import 'package:dartc/compiler.dart';
import 'package:dartc/artifact.dart';

import 'dart:io';

import 'package:dartc/formats.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/abi/fixtures/frames.dart';
import '../test/codegen/fixtures/control_flow.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/calls.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/support/native_assets.dart';

Future<void> main() async {
  for (final os in OperatingSystem.values) {
    for (final arch in Architecture.values) {
      final target = Target(os, arch);
      final assets = NativeAssets(target);
      for (final domain in ['abi', 'compiler', 'codegen', 'linker']) {
        await Directory.fromUri(assets.directory.uri.resolve('$domain/'))
            .create(recursive: true);
      }
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

      final calls = await Compiler(target)
          .compile(['test/compiler/fixtures/calls.dart']);
      await calls.write(assets.library('compiler/calls'), kind: .sharedLibrary);
      await calls.write(assets.file('compiler/calls.o'));
      await calls.write(assets.file('compiler/calls.a'), kind: .staticLibrary);

      final flowLibrary = await Compiler(target)
          .compile(['test/compiler/fixtures/control_flow.dart']);
      await flowLibrary.write(
        assets.library('compiler/control_flow'),
        kind: .sharedLibrary,
      );
      await flowLibrary.write(assets.file('compiler/control_flow.o'));
      await flowLibrary.write(
        assets.file('compiler/control_flow.a'),
        kind: .staticLibrary,
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
      await shared([frames(target)], assets.library('abi/frames'));
      await shared([
        controlFlow(target),
      ], assets.library('codegen/control_flow'));
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
      final modules = callModules(target);
      await shared(modules, assets.library('linker/calls'));
      await assets
          .file('linker/calls.a')
          .writeAsBytes(ArchiveWriter(format).encode(modules));
      for (final (i, module) in modules.indexed) {
        await assets
            .file('linker/call_$i.o')
            .writeAsBytes(format.encodeObject(module));
      }
      print('Built test assets for $target.');
    }
  }
}
