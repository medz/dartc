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
import '../test/compiler/fixtures/native_addresses_ffi.dart'
    show nativeAddressSymbols;
import '../test/compiler/fixtures/entry/assets.dart';
import '../test/abi/fixtures/frames.dart';
import '../test/abi/fixtures/floating_frames.dart';
import '../test/abi/fixtures/stack_calls.dart';
import '../test/codegen/fixtures/control_flow.dart';
import '../test/codegen/fixtures/object_values.dart';
import '../test/codegen/fixtures/boxed_values.dart';
import '../test/codegen/fixtures/stack_roots.dart';
import '../test/codegen/fixtures/managed_heap.dart';
import '../test/codegen/fixtures/weak_heap.dart';
import '../test/codegen/fixtures/dynamic_boxes.dart';
import '../test/codegen/fixtures/exceptions.dart';
import '../test/linker/fixtures/functions.dart';
import '../test/linker/fixtures/calls.dart';
import '../test/linker/fixtures/symbols.dart';
import '../test/linker/fixtures/data.dart';
import '../test/linker/fixtures/archive.dart';
import '../test/linker/fixtures/shared_libraries.dart';
import '../test/linker/fixtures/addresses.dart';
import '../test/linker/fixtures/finalizers.dart';
import '../test/compiler/fixtures/descriptor_write_assets.dart';
import '../test/compiler/fixtures/managed_objects_assets.dart';
import '../test/compiler/fixtures/random_entropy_assets.dart';
import '../test/compiler/fixtures/native_finalizers_assets.dart';
import '../test/compiler/fixtures/native_symbols_assets.dart';
import '../test/support/native_assets.dart';
import '../test/support/runtime.dart';

const _compilerLibraries = {
  'arithmetic',
  'calls',
  'closures',
  'function_values',
  'bound_methods',
  'function_instantiation',
  'control_flow',
  'nullability',
  'stack_calls',
  'integer_operations',
  'numeric_conversions',
  'numeric_methods',
  'integer_text',
  'boolean_text',
  'scalar_globals',
  'managed_globals',
  'late_fields',
  'late_locals',
  'pointers',
  'pointer_arithmetic',
  'pointer_values',
  'strings',
  'lists',
  'maps',
  'doubles',
  'mixed_numeric',
  'math',
  'native_integers',
  'abi_integers',
  'native_floats',
  'native_function_pointers',
  'native_imports',
  'native_addresses',
  'native_callbacks',
  'native_callbacks_plain',
  'native_callables',
  'varargs',
  'varargs_scalar',
  'dynamic_library_provider',
  'native_aggregates',
  'typed_data',
  'managed_objects',
  'heap_runtime',
  'weak_references',
  'expandos',
  'finalizers',
  'native_finalizers',
  'native_symbols',
  'string_operations',
  'numeric_boxes',
  'exceptions',
  'type_checks',
  'type_arguments',
  'class_types',
  'member_calls',
  'object_members',
  'object_text',
};

Set<String> selectCompilerFixtures(Iterable<String> names) {
  const available = {
    ..._compilerLibraries,
    'entry',
    'descriptor_write',
    'futures',
    'async_functions',
    'async_stack_traces',
    'sync_generators',
    'async_generators',
    'records',
    'enums',
    'symbols',
    'base64_conversion',
    'math_random',
    'bigint',
    'text_conversion',
    'stopwatch',
    'date_time',
    'regexp_escape',
  };
  final selected = names.toSet();
  if (selected.contains('native_callbacks')) {
    selected.add('native_callbacks_plain');
  }
  if (selected.contains('varargs')) selected.add('varargs_scalar');
  final unknown = selected.difference(available);
  if (unknown.isNotEmpty) {
    throw ArgumentError('Unknown compiler fixtures: ${unknown.join(', ')}');
  }
  if (selected.isEmpty) return available;
  if (selected.contains('native_imports') ||
      selected.contains('pointer_values')) {
    selected.add('native_function_pointers');
  }
  return selected;
}

Future<void> main(List<String> args) async {
  const prefix = '--fixture=';
  final requested = args.where((arg) => arg.startsWith(prefix)).toList();
  final selected = selectCompilerFixtures(
    requested.map((arg) => arg.substring(prefix.length)),
  );
  final targetNames = args.where((arg) => !arg.startsWith(prefix)).toList();
  final targets = targetNames.isEmpty
      ? [
          for (final os in OperatingSystem.values)
            for (final arch in Architecture.values) Target(os, arch),
        ]
      : targetNames.map(Target.parse).toList();
  if (requested.isEmpty) await prepareRuntime();
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
    Future<void> shared(
      List<ObjectModule> modules,
      File output, {
      Iterable<LinkInput> dependencies = const [],
    }) => output.writeAsBytes(
      linker.linkSharedLibrary([
        ...modules.map(LinkInput.object),
        ...dependencies,
      ], name: output.uri.pathSegments.last),
    );

    if (selected.contains('entry')) {
      for (final fixture in [
        'return',
        'void',
        'status',
        'exported',
        'math',
        'arguments',
        'arguments_async',
        'arguments_optional',
        'arguments_named',
        'arguments_generic',
      ]) {
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
      if (target.operatingSystem == .linux) {
        for (final (name, library) in [
          ('dynamic', 'libc.so.6'),
          ('arguments_dynamic', 'libc.so.6'),
          ('missing', 'libdartc_missing_dependency.so'),
        ]) {
          final result = await Compiler(target).compile(
            ['test/compiler/fixtures/entry/${name == 'arguments_dynamic' ? 'arguments' : 'return'}.dart'],
            output: const .executable(),
            linkInputs: [.sharedLibrary(library)],
          );
          await result.write(assets.file('compiler/entry_$name'));
        }
      }
    }

    for (final (fixture, source, output) in [
      ('managed_objects', 'managed_objects', 'entry_managed'),
      ('lists', 'lists_overflow', 'entry_lists_overflow'),
      ('managed_globals', 'managed_globals', 'entry_managed_globals'),
      ('exceptions', 'exceptions', 'entry_exception'),
      ('finalizers', 'finalizers_entry', 'entry_finalizers'),
      ('finalizers', 'finalizers_error', 'entry_finalizers_error'),
      ('futures', 'futures', 'entry_futures'),
      ('async_functions', 'async_functions', 'entry_async_functions'),
      ('async_functions', 'async_error', 'entry_async_error'),
      ('async_stack_traces', 'async_stack_traces', 'entry_async_stack_traces'),
      (
        'async_stack_traces',
        'callback_stack_locations',
        'entry_callback_stack_locations',
      ),
      ('sync_generators', 'sync_generators', 'entry_sync_generators'),
      ('sync_generators', 'sync_reentry', 'entry_sync_reentry'),
      ('async_generators', 'async_generators', 'entry_async_generators'),
      (
        'async_generators',
        'async_generator_recovery',
        'entry_async_generator_recovery',
      ),
      ('records', 'records', 'entry_records'),
      ('enums', 'enums', 'entry_enums'),
      ('symbols', 'symbols', 'entry_symbols'),
      ('base64_conversion', 'base64_conversion', 'entry_base64_conversion'),
      ('math_random', 'math_random', 'entry_math_random'),
      ('bigint', 'bigint', 'entry_bigint'),
      ('text_conversion', 'text_conversion', 'entry_text_conversion'),
      ('stopwatch', 'stopwatch', 'entry_stopwatch'),
      ('date_time', 'date_time', 'entry_date_time'),
      ('regexp_escape', 'regexp_escape', 'entry_regexp_escape'),
      ('native_callables', 'native_callables', 'entry_native_callables'),
      (
        'dynamic_library_provider',
        'dynamic_libraries',
        'entry_dynamic_libraries',
      ),
      (
        'native_callables',
        'native_callables_alive',
        'entry_native_callables_alive',
      ),
      (
        'native_callables',
        'native_callables_idle',
        'entry_native_callables_idle',
      ),
    ]) {
      if (!selected.contains(fixture)) continue;
      final entry = await Compiler(target).compile([
        'test/compiler/fixtures/$source.dart',
      ], output: const .executable());
      await entry.write(assets.file('compiler/$output'));
    }
    if (selected.contains('varargs')) {
      final source = Uri.base.resolve('test/compiler/fixtures/varargs.dart');
      final entry = await Compiler(target).compile(
        [source.toFilePath()],
        output: const .executable(),
        nativeSymbols: {
          source.toString(): {'snprintf': 'snprintf'},
        },
        linkInputs: [
          LinkInput.sharedLibrary(
            target.operatingSystem == .macos
                ? '/usr/lib/libSystem.B.dylib'
                : 'libc.so.6',
            symbols: {
              target.nativeSymbol('snprintf'): target.nativeSymbol('snprintf'),
            },
          ),
        ],
      );
      await entry.write(assets.file('compiler/entry_varargs'));
    }
    if (target == const Target(.linux, .arm64) &&
        selected.contains('math_random')) {
      for (final source in ['random_unavailable', 'random_source_lost']) {
        final failure = await Compiler(target).compile(
          ['test/compiler/fixtures/$source.dart'],
          output: const .executable(),
          nativeSymbols: const {
            'entropy-test': {'deny': 'deny_entropy'},
          },
          linkInputs: [.object(denyEntropy())],
        );
        await failure.write(assets.file('compiler/entry_$source'));
      }
    }
    if (target.operatingSystem == .linux) {
      for (final (fixture, name) in [
        ('managed_objects', 'managed_failure'),
        ('managed_objects', 'managed_growth_failure'),
        ('managed_objects', 'managed_recovery'),
        ('numeric_boxes', 'boxing_null_entry'),
      ]) {
        if (!selected.contains(fixture)) continue;
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

    if (selected.contains('descriptor_write')) {
      final io = await Compiler(target).compile([
        'test/compiler/fixtures/descriptor_write.dart',
      ], nativeSymbols: ioSymbols);
      final scriptedIo = await Compiler(target).compile([
        'test/compiler/fixtures/scripted_write.dart',
      ], nativeSymbols: ioSymbols);
      await io.write(assets.file('compiler/descriptor_write.o'));
      await scriptedIo.write(assets.file('compiler/scripted_write.o'));
      final ioModule = format.decodeObject(io.bytes),
          storage = ioStorage(target);
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
                target.operatingSystem == .macos
                    ? '__error'
                    : '__errno_location',
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
    }

    for (final fixture in _compilerLibraries.where(selected.contains)) {
      final library = assets.library('compiler/$fixture');
      final result = await Compiler(target).compile(
        ['test/compiler/fixtures/$fixture.dart'],
        nativeSymbols: switch (fixture) {
          'native_imports' => nativeImportSymbols,
          'native_addresses' => nativeAddressSymbols,
          'native_symbols' => nativeSymbols,
          _ => const {},
        },
      );
      await result.write(
        assets.file('compiler/$fixture.o'),
        header: switch (fixture) {
          'arithmetic' ||
          'pointers' ||
          'doubles' ||
          'mixed_numeric' ||
          'native_integers' ||
          'abi_integers' ||
          'native_floats' ||
          'native_function_pointers' ||
          'native_imports' ||
          'native_symbols' ||
          'native_aggregates' => assets.file('compiler/$fixture.h'),
          _ => null,
        },
      );
      final module = format.decodeObject(result.bytes);
      await assets
          .file('compiler/$fixture.a')
          .writeAsBytes(ArchiveWriter(format).encode([module]));
      await shared(
        [
          module,
          if (fixture == 'native_symbols') nativeSymbolsProvider(target),
          if (fixture == 'native_imports')
            format.decodeObject(
              await assets
                  .file('compiler/native_function_pointers.o')
                  .readAsBytes(),
            ),
        ],
        library,
        dependencies: [
          ...result.dependencies,
          if (fixture == 'native_addresses')
            .sharedLibrary(
              target.operatingSystem == .macos
                  ? '/usr/lib/libSystem.B.dylib'
                  : 'libc.so.6',
              symbols: {
                target.nativeSymbol('memmove'): target.nativeSymbol('memmove'),
              },
            ),
        ],
      );
      if (fixture == 'dynamic_library_provider') {
        await library.copy(assets.library('compiler/动态库').path);
      }
      if (fixture == 'native_symbols') {
        await shared([
          nativeSymbolsProvider(target),
        ], assets.library('compiler/native_symbols_provider'));
      }
      if (fixture == 'native_imports' || fixture == 'native_symbols') {
        final dynamicLibrary = assets.library('compiler/${fixture}_dynamic');
        await dynamicLibrary.writeAsBytes(
          linker.linkSharedLibrary([
            .object(module),
            dependency(
              target,
              fixture == 'native_imports'
                  ? 'native_function_pointers'
                  : 'native_symbols_provider',
              {for (final name in module.imports) name: name},
            ),
          ], name: dynamicLibrary.uri.pathSegments.last),
        );
      }
    }
    const storageFixtures = {
      'doubles',
      'mixed_numeric',
      'math',
      'pointers',
      'managed_objects',
      'exceptions',
      'type_checks',
      'native_integers',
      'abi_integers',
      'native_floats',
      'pointer_arithmetic',
    };
    if (selected.contains('native_finalizers')) {
      await shared([
        nativeFinalizerCallback(target),
      ], assets.library('compiler/native_finalizer_callback'));
      final entry = await Compiler(target).compile(
        ['test/compiler/fixtures/native_finalizers_entry.dart'],
        output: const .executable(),
        nativeSymbols: const {
          'finalizer-test': {'finish': 'finalizer_exit'},
        },
        linkInputs: [.object(nativeFinalizerExit(target))],
      );
      await entry.write(assets.file('compiler/entry_native_finalizers'));
    }
    late final data = dataModules(target);
    for (final fixture in selected.where(storageFixtures.contains)) {
      await shared([data.first], assets.library('compiler/${fixture}_storage'));
    }
    if (requested.isNotEmpty) {
      print('Built compiler fixtures ${selected.join(', ')} for $target.');
      continue;
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
      dependencies: [
        LinkInput.sharedLibrary(
          target.operatingSystem == .macos
              ? '/usr/lib/libSystem.B.dylib'
              : 'libc.so.6',
          symbols: {target.nativeSymbol('qsort'): target.nativeSymbol('qsort')},
        ),
      ],
    );
    await shared([
      exceptions(target),
      rootsProbe(target),
    ], assets.library('codegen/exceptions'));
    await shared([weakHeap(target)], assets.library('codegen/weak_heap'));
    final finalizers = await objects('finalizers_', finalizerModules(target));
    await shared(finalizers, assets.library('linker/finalizers'));
    final finalizerArchive = Archive.decode(
      ArchiveWriter(format).encode([finalizers.last]),
    );
    final finalizerLibrary = assets.library('linker/finalizers_archive');
    await finalizerLibrary.writeAsBytes(
      linker.linkSharedLibrary([
        LinkInput.object(finalizers.first),
        LinkInput.object(
          ObjectModule(
            target,
            [],
            [],
            imports: [target.nativeSymbol('marker_1')],
          ),
        ),
        LinkInput.archive(finalizerArchive),
      ], name: finalizerLibrary.uri.pathSegments.last),
    );
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
