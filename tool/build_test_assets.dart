import 'dart:io';

import 'package:dartc/abi.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/object.dart';
import 'package:dartc/object/elf.dart';
import 'package:dartc/object/mach_o.dart';
import 'package:dartc/target.dart';

import '../test/codegen/fixtures/aliases.dart';
import '../test/codegen/fixtures/native_calls.dart';
import '../test/compiler/fixtures/native_imports_ffi.dart'
    show nativeImportSymbols;
import '../test/compiler/fixtures/entry/assets.dart';
import '../test/abi/fixtures/frames.dart';
import '../test/abi/fixtures/floating_frames.dart';
import '../test/abi/fixtures/stack_calls.dart';
import '../test/codegen/fixtures/control_flow.dart';
import '../test/codegen/fixtures/object_values.dart';
import '../test/codegen/fixtures/boxed_values.dart';
import '../test/codegen/fixtures/stack_roots.dart';
import '../test/codegen/fixtures/managed_heap.dart';
import '../test/codegen/fixtures/dynamic_boxes.dart';
import '../test/codegen/fixtures/exceptions.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/calls.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/linker/fixtures/data.dart';
import '../test/linker/fixtures/archive.dart';
import '../test/linker/fixtures/shared_libraries.dart';
import '../test/linker/fixtures/addresses.dart';
import '../test/compiler/fixtures/descriptor_write_assets.dart';
import '../test/compiler/fixtures/managed_objects_assets.dart';
import '../test/support/native_assets.dart';
import 'build_compiler_test_assets.dart' as compiler_assets;

Future<void> main(List<String> args) async {
  await compiler_assets.main();
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

    for (final fixture in ['return', 'void', 'status', 'exported', 'math']) {
      final needsBindings =
          fixture == 'status' || fixture == 'exported' || fixture == 'math';
      final result = await Compiler(target).compile(
        ['test/compiler/fixtures/entry/$fixture.dart'],
        output: const .executable(),
        nativeSymbols: needsBindings ? entrySymbols : const {},
        linkInputs: needsBindings ? entryInputs(target) : const [],
      );
      await result.write(assets.file('compiler/entry_$fixture'));
    }

    final managedEntry = await Compiler(target).compile([
      'test/compiler/fixtures/managed_objects.dart',
    ], output: const .executable());
    await managedEntry.write(assets.file('compiler/entry_managed'));
    final exceptionEntry = await Compiler(target).compile([
      'test/compiler/fixtures/exceptions.dart',
    ], output: const .executable());
    await exceptionEntry.write(assets.file('compiler/entry_exception'));
    if (target.operatingSystem == .linux) {
      for (final name in [
        'managed_failure',
        'managed_growth_failure',
        'boxing_null_entry',
      ]) {
        final failure = await Compiler(target).compile(
          ['test/compiler/fixtures/$name.dart'],
          output: const .executable(),
          nativeSymbols: const {
            'heap-test': {'limit': 'heap_limit'},
          },
          linkInputs: [.object(restrictAddressSpace(target))],
        );
        await failure.write(assets.file('compiler/$name'));
      }
    }

    final io = await Compiler(target).compile([
      'test/compiler/fixtures/descriptor_write.dart',
    ], nativeSymbols: ioSymbols);
    final scriptedIo = await Compiler(target).compile([
      'test/compiler/fixtures/scripted_write.dart',
    ], nativeSymbols: ioSymbols);
    await io.write(assets.file('compiler/descriptor_write.o'));
    await scriptedIo.write(assets.file('compiler/scripted_write.o'));
    final ioModule = format.decodeObject(io.bytes), storage = ioStorage(target);
    final ioLibrary = assets.library('compiler/descriptor_write');
    await ioLibrary.writeAsBytes(
      linker.linkSharedLibrary([
        .object(ioModule),
        .object(storage),
        .sharedLibrary(
          target.operatingSystem == .macos
              ? '/usr/lib/libSystem.B.dylib'
              : 'libc.so.6',
          symbols: {
            target.nativeSymbol('test_write'): target.nativeSymbol('write'),
            target.nativeSymbol('test_errno'): target.nativeSymbol(
              target.operatingSystem == .macos ? '__error' : '__errno_location',
            ),
          },
        ),
      ], name: ioLibrary.uri.pathSegments.last),
    );
    await shared([
      ioModule,
      format.decodeObject(scriptedIo.bytes),
      storage,
    ], assets.library('compiler/descriptor_write_scripted'));

    for (final fixture in [
      'arithmetic',
      'calls',
      'control_flow',
      'nullability',
      'stack_calls',
      'integer_operations',
      'pointers',
      'pointer_arithmetic',
      'doubles',
      'mixed_numeric',
      'math',
      'native_integers',
      'native_floats',
      'native_function_pointers',
      'native_imports',
      'managed_objects',
      'numeric_boxes',
      'exceptions',
    ]) {
      final library = assets.library('compiler/$fixture');
      final result = await Compiler(target).compile(
        ['test/compiler/fixtures/$fixture.dart'],
        nativeSymbols: fixture == 'native_imports'
            ? nativeImportSymbols
            : const {},
      );
      await result.write(
        assets.file('compiler/$fixture.o'),
        header: switch (fixture) {
          'arithmetic' ||
          'pointers' ||
          'doubles' ||
          'mixed_numeric' ||
          'native_integers' ||
          'native_floats' ||
          'native_function_pointers' ||
          'native_imports' => assets.file('compiler/$fixture.h'),
          _ => null,
        },
      );
      final module = format.decodeObject(result.bytes);
      await assets
          .file('compiler/$fixture.a')
          .writeAsBytes(ArchiveWriter(format).encode([module]));
      await shared([
        module,
        if (fixture == 'native_imports')
          format.decodeObject(
            await assets
                .file('compiler/native_function_pointers.o')
                .readAsBytes(),
          ),
      ], library);
      if (fixture == 'native_imports') {
        final dynamicLibrary = assets.library(
          'compiler/native_imports_dynamic',
        );
        await dynamicLibrary.writeAsBytes(
          linker.linkSharedLibrary([
            .object(module),
            dependency(target, 'native_function_pointers', {
              for (final name in module.imports) name: name,
            }),
          ], name: dynamicLibrary.uri.pathSegments.last),
        );
      }
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
    final nativeModules = await objects('native_calls_', nativeCalls(target));
    await shared(nativeModules, assets.library('codegen/native_calls'));
    await shared([
      nativeModules.last,
    ], assets.library('linker/native_provider'));
    final nativeLibrary = assets.library('linker/native_calls');
    await nativeLibrary.writeAsBytes(
      linker.linkSharedLibrary([
        .object(nativeModules.first),
        dependency(target, 'native_provider', {
          for (final name in nativeModules.first.imports) name: name,
        }),
      ], name: nativeLibrary.uri.pathSegments.last),
    );
    await shared([frames(target)], assets.library('abi/frames'));
    await shared(stackCalls(target), assets.library('abi/stack_calls'));
    await shared([controlFlow(target)], assets.library('codegen/control_flow'));
    await shared([
      objectValues(target),
      functions(target, {'object_touch': 123}),
    ], assets.library('codegen/object_values'));
    await shared([boxedValues(target)], assets.library('codegen/boxed_values'));
    await shared([
      dynamicBoxes(target),
    ], assets.library('codegen/dynamic_boxes'));
    await shared(
      await objects('stack_roots_', [stackRoots(target), rootsProbe(target)]),
      assets.library('codegen/stack_roots'),
    );
    await shared(
      await objects('managed_heap_', [managedHeap(target)]),
      assets.library('codegen/managed_heap'),
    );
    await shared([
      exceptions(target),
      rootsProbe(target),
    ], assets.library('codegen/exceptions'));
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
    await shared([decodedData.first], assets.library('linker/storage'));
    final addresses = await objects('addresses_', addressModules(target));
    await shared(
      await objects('address_table_', [constantAddressTable(target)]),
      assets.library('linker/addresses_constant'),
    );
    await shared([
      addresses.first,
    ], assets.library('linker/addresses_provider'));
    await shared(addresses, assets.library('linker/addresses_static'));
    final addressArchive = assets.file('linker/addresses.a');
    await addressArchive.writeAsBytes(
      ArchiveWriter(format).encode([addresses.first]),
    );
    for (final (name, provider) in <(String, LinkInput)>[
      (
        'addresses_archive',
        .archive(Archive.decode(await addressArchive.readAsBytes())),
      ),
      (
        'addresses_shared',
        dependency(target, 'addresses_provider', {
          for (final name in addresses[1].imports) name: name,
        }),
      ),
    ]) {
      final library = assets.library('linker/$name');
      await library.writeAsBytes(
        linker.linkSharedLibrary([
          for (final consumer in addresses.skip(1)) .object(consumer),
          provider,
        ], name: library.uri.pathSegments.last),
      );
    }
    for (final name in [
      'double',
      'numeric',
      'pointer',
      'integer',
      'float',
      'index',
    ]) {
      await shared([
        decodedData.first,
      ], assets.library('compiler/${name}_storage'));
    }
    await assets
        .file('linker/data.a')
        .writeAsBytes(ArchiveWriter(format).encode(data));
    final modules = callModules(target);
    for (final entry in sharedLibraries(target).entries) {
      final name = entry.key;
      final library = assets.library('linker/$name');
      await library.writeAsBytes(
        linker.linkSharedLibrary(
          entry.value,
          name: library.uri.pathSegments.last,
        ),
      );
    }
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
