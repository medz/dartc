import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/abi/fixtures/frames.dart';
import '../test/abi/fixtures/floating_frames.dart';
import '../test/abi/fixtures/stack_calls.dart';
import '../test/codegen/fixtures/control_flow.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/calls.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/linker/fixtures/data.dart';
import '../test/linker/fixtures/archive.dart';
import '../test/support/native_assets.dart';

Future<void> main(List<String> args) async {
  final targets = args.isEmpty
      ? [
          for (final os in OperatingSystem.values)
            for (final arch in Architecture.values) Target(os, arch),
        ]
      : args.map(Target.parse).toList();
  for (final target in targets) {
    final ObjectFormat format = switch (target.operatingSystem) {
      .macos => MachO(target),
      .linux => Elf(target),
    };
    final Linker linker = switch (target.operatingSystem) {
      .macos => MachOLinker(target),
      .linux => ElfLinker(target),
    };
    final assets = NativeAssets(target);
    for (final domain in ['abi', 'compiler', 'codegen', 'linker']) {
      await Directory.fromUri(assets.directory.uri.resolve('$domain/'))
          .create(recursive: true);
    }
    Future<void> shared(List<ObjectModule> modules, File output) =>
        output.writeAsBytes(
          linker.linkSharedLibrary(
            modules.map(LinkInput.object),
            name: output.uri.pathSegments.last,
          ),
        );

    for (final fixture in [
      'arithmetic',
      'calls',
      'control_flow',
      'stack_calls',
      'integer_operations',
      'pointers',
      'doubles',
      'mixed_numeric',
      'native_integers',
    ]) {
      final library = assets.library('compiler/$fixture');
      final result = await Compiler(target)
          .compile(['test/compiler/fixtures/$fixture.dart']);
      await result.write(
        assets.file('compiler/$fixture.o'),
        header: switch (fixture) {
          'arithmetic' ||
          'pointers' ||
          'doubles' ||
          'mixed_numeric' ||
          'native_integers' => assets.file('compiler/$fixture.h'),
          _ => null,
        },
      );
      final module = format.decodeObject(result.bytes);
      await assets
          .file('compiler/$fixture.a')
          .writeAsBytes(ArchiveWriter(format).encode([module]));
      await shared([module], library);
    }
    await shared([
      floatingFrames(target),
    ], assets.library('abi/floating_frames'));
    Future<List<ObjectModule>> objects(
      String name,
      List<ObjectModule> modules,
    ) async {
      final decoded = <ObjectModule>[];
      for (final (i, module) in modules.indexed) {
        final file = assets.file('linker/$name$i.o');
        await file.writeAsBytes(format.encodeObject(module));
        decoded.add(format.decodeObject(await file.readAsBytes()));
      }
      return decoded;
    }

    await shared([aliases(target)], assets.library('codegen/aliases'));
    await shared([frames(target)], assets.library('abi/frames'));
    await shared(stackCalls(target), assets.library('abi/stack_calls'));
    await shared([controlFlow(target)], assets.library('codegen/control_flow'));
    final inputs = [
      functions(target, {'first': 40}),
      functions(target, {'second': 2}),
    ];
    await assets
        .file('linker/values.a')
        .writeAsBytes(ArchiveWriter(format).encode(inputs));
    await shared(await objects('', inputs), assets.library('linker/values'));
    await shared([
      functions(target, symbolValues),
    ], assets.library('linker/symbols'));
    final data = dataModules(target);
    final decodedData = await objects('data_', data);
    await shared(decodedData, assets.library('linker/data'));
    await shared([
      decodedData.first,
    ], assets.library('compiler/double_storage'));
    await shared([
      decodedData.first,
    ], assets.library('compiler/numeric_storage'));
    await shared([decodedData.first], assets.library('linker/storage'));
    await shared([
      decodedData.first,
    ], assets.library('compiler/pointer_storage'));
    await assets
        .file('linker/data.a')
        .writeAsBytes(ArchiveWriter(format).encode(data));
    final modules = callModules(target);
    await shared(
      await objects('call_', modules),
      assets.library('linker/calls'),
    );
    await assets
        .file('linker/calls.a')
        .writeAsBytes(ArchiveWriter(format).encode(modules));
    final lazy = archiveModules(target);
    final roots = await objects('lazy_', [lazy.first]);
    final archive = assets.file('linker/lazy.a');
    await archive.writeAsBytes(ArchiveWriter(format).encode(lazy.skip(1)));
    for (final (name, root, archiveFile) in [
      ('archive_calls', roots.single, archive),
      ('archive_data', decodedData.last, assets.file('linker/data.a')),
    ]) {
      final output = assets.library('linker/$name');
      await output.writeAsBytes(
        linker.linkSharedLibrary([
          .object(root),
          .archive(Archive.decode(await archiveFile.readAsBytes())),
        ], name: output.uri.pathSegments.last),
      );
    }
    print('Built test assets for $target.');
  }
}
