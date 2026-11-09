import 'package:dartc/compiler.dart';
import 'package:dartc/object.dart';

import 'dart:io';

import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/abi/fixtures/frames.dart';
import '../test/abi/fixtures/stack_calls.dart';
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
      for (final fixture in [
        'arithmetic',
        'calls',
        'control_flow',
        'stack_calls',
      ]) {
        final library = assets.library('compiler/$fixture');
        for (final (file, output) in <(File, Output)>[
          (assets.file('compiler/$fixture.o'), const .object()),
          (assets.file('compiler/$fixture.a'), const .staticLibrary()),
          (library, .sharedLibrary(library.uri.pathSegments.last)),
        ]) {
          final result = await Compiler(
            target,
          ).compile(['test/compiler/fixtures/$fixture.dart'], output: output);
          await result.write(
            file,
            header: fixture == 'arithmetic' && output is ObjectOutput
                ? assets.file('compiler/arithmetic.h')
                : null,
          );
        }
      }

      final ObjectFormat format = switch (os) {
        .macos => MachO(target),
        .linux => Elf(target),
      };
      final Linker linker = switch (os) {
        .macos => MachOLinker(target),
        .linux => ElfLinker(target),
      };
      Future<void> shared(List<ObjectModule> modules, File output) =>
          output.writeAsBytes(
            linker.linkSharedLibrary(
              modules,
              name: output.uri.pathSegments.last,
            ),
          );
      await shared([aliases(target)], assets.library('codegen/aliases'));
      await shared([frames(target)], assets.library('abi/frames'));
      await shared(stackCalls(target), assets.library('abi/stack_calls'));
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
