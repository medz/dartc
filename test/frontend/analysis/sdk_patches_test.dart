import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
// SDK patch fragments require the same SDK-specific experiment view as compilation.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/src/frontend/analyzer_metadata.dart';
import 'package:dartc/src/frontend/analysis/sdk_patches.dart';
import 'package:dartc/src/frontend/analysis/source_files.dart';
import 'package:test/test.dart';

Future<void> withImplementations(
  void Function(List<ResolvedLibraryResult>, SdkPatches) check, {
  String Function(String)? change,
}) async {
  final archive = await SdkSources.load();
  const root = '/__dartc__', runtime = '$root/sdk/patches';
  final files = OverlayResourceProvider(
    SourceFiles(archive, root, extraSources: archive),
  );
  if (change != null) {
    final path = '$runtime/core.dart';
    files.setOverlay(
      path,
      content: change(files.getFile(path).readAsStringSync()),
      modificationStamp: 0,
    );
  }
  final patches = SdkPatches(files)..install('$root/sdk/std', runtime);
  final input = File('test/compiler/fixtures/expandos.dart').absolute.path;
  final contexts = AnalysisContextCollectionImpl(
    includedPaths: [input],
    resourceProvider: files,
    sdkPath: '$root/sdk/std',
  );
  try {
    final session = contexts.contextFor(input).currentSession;
    final user =
        await session.getResolvedLibrary(input) as ResolvedLibraryResult;
    final pending = [user.element.typeProvider.objectElement.library];
    final libraries = <ResolvedLibraryResult>[user];
    for (var i = 0; i < pending.length; i++) {
      final library = pending[i];
      prepareSdkLibrary(library);
      libraries.add(
        await session.getResolvedLibraryByElement(library)
            as ResolvedLibraryResult,
      );
      for (final imported in library.fragments.expand(
        (f) => f.importedLibraries,
      )) {
        if (const {
              'dart:core',
              'dart:_internal',
              'dart:_vm',
              'dart:async',
              'dart:collection',
              'dart:_compact_hash',
              'dart:convert',
              'dart:ffi',
              'dart:typed_data',
            }.contains(imported.uri.toString()) &&
            !pending.contains(imported)) {
          pending.add(imported);
        }
      }
    }
    check(libraries, patches);
  } finally {
    await contexts.dispose();
  }
}

void main() {
  test(
    'all installed SDK implementation units are analyzed in their library',
    () async {
      await withImplementations((libraries, patches) {
        final units = libraries.expand((library) => library.units).toList();
        expect([
          for (final unit in units)
            ...unit.diagnostics.where((d) => d.severity == .error),
        ], isEmpty);
        final analyzed = {for (final unit in units) unit.uri};
        expect(analyzed, containsAll(patches.origins.keys));
        final internal = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:_internal'),
        );
        expect(
          internal.element.topLevelFunctions
              .singleWhere((function) => function.name == 'unsafeCast')
              .isExternal,
          isTrue,
        );
        final async = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:async'),
        );
        for (final (type, name) in [
          ('_Future', 'then'),
          ('_Completer', 'completeError'),
        ]) {
          final member = async.element.getClass(type)!.getMethod(name)!;
          expect(member.fragments, hasLength(1));
          final body = async.getFragmentDeclaration(member.firstFragment)!;
          expect(
            body.resolvedUnit!.uri.toString(),
            'dart:async/future_impl.dart',
          );
        }
        final awaitBody = async.getFragmentDeclaration(
          async.element
              .getClass('_SuspendState')!
              .getMethod('_awaitWithTypeCheck')!
              .firstFragment,
        )!;
        expect(
          patches.origins[awaitBody.resolvedUnit!.uri]!.path,
          endsWith('/_internal/vm/lib/async_patch.dart'),
        );
        final ffi = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:ffi'),
        );
        final size = ffi.element.getClass('_ArraySize')!;
        for (final name in ['_typedDataBase', '_offsetInBytes']) {
          final source = ffi.getFragmentDeclaration(
            size.getGetter(name)!.firstFragment,
          )!;
          expect(
            patches.origins[source.resolvedUnit!.uri]!.path,
            endsWith('/ffi_patch.dart'),
          );
        }
        final collection = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:collection'),
        );
        final typedData = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:typed_data'),
        );
        final typedMixin = typedData.element.mixins.singleWhere(
          (mixin) => mixin.name == '_TypedListMixin',
        );
        for (final member in [
          typedData.element
              .getClass('Uint8List')!
              .getNamedConstructor('fromList')!,
          typedData.element.getClass('ByteData')!.unnamedConstructor!,
          typedData.element.getClass('_ByteDataView')!.getMethod('getFloat64')!,
          typedMixin.getMethod('sublist')!,
          typedMixin.getMethod('setRange')!,
        ]) {
          final body = typedData.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith('/vm/lib/typed_data_patch.dart'),
          );
        }
        expect(
          typedData.element
              .getTopLevelFunction('_uint8ListRangeEquals')!
              .fragments,
          hasLength(1),
        );
        for (final name in ['_HashMap', '_HashSet', '_CustomHashMap']) {
          final source = collection.getFragmentDeclaration(
            collection.element.getClass(name)!.firstFragment,
          )!;
          expect(
            patches.origins[source.resolvedUnit!.uri]!.path,
            endsWith('/vm_shared/lib/collection_patch.dart'),
          );
        }
        for (final name in ['LinkedHashMap', 'LinkedHashSet']) {
          final constructor = collection.element
              .getClass(name)!
              .unnamedConstructor!;
          final body = collection.getFragmentDeclaration(
            constructor.fragments.last,
          )!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith('/vm/lib/hash_factories.dart'),
          );
        }
        final convert = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:convert'),
        );
        for (final fragment in [
          convert.element.getTopLevelFunction('_parseJson')!.fragments.last,
          convert.element.getClass('_JsonStringParser')!.firstFragment,
          convert.element
              .getClass('_Utf8Decoder')!
              .getMethod('convertSingle')!
              .fragments
              .last,
        ]) {
          final body = convert.getFragmentDeclaration(fragment)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith('/vm/lib/convert_patch.dart'),
          );
        }
        final core = libraries.singleWhere(
          (library) => library.element.isDartCore,
        );
        for (final member in [
          core.element
              .getClass('StackTrace')!
              .getNamedConstructor('fromString')!,
          core.element.getClass('_StringStackTrace')!.getMethod('toString')!,
        ]) {
          expect(member.fragments, hasLength(1));
          final body = core.getFragmentDeclaration(member.firstFragment)!;
          expect(
            body.resolvedUnit!.uri.toString(),
            'dart:core/stacktrace.dart',
          );
        }
        for (final (type, method, source) in [
          ('int', 'parse', '/vm_shared/lib/integers_patch.dart'),
          ('int', 'tryParse', '/vm_shared/lib/integers_patch.dart'),
          ('double', 'parse', '/vm/lib/double_patch.dart'),
          ('double', 'tryParse', '/vm/lib/double_patch.dart'),
          ('double', '_nativeParse', '/sdk/patches/double.dart'),
          ('_Record', '==', '/vm/lib/record_patch.dart'),
          ('_Record', 'toString', '/vm/lib/record_patch.dart'),
          ('StringBuffer', 'write', '/vm_shared/lib/string_buffer_patch.dart'),
          (
            'StringBuffer',
            'toString',
            '/vm_shared/lib/string_buffer_patch.dart',
          ),
          ('StringBuffer', '_create', '/sdk/patches/string.dart'),
          ('_StringBase', 'trim', '/vm/lib/string_patch.dart'),
          ('_StringBase', 'indexOf', '/vm/lib/string_patch.dart'),
          ('_StringBase', 'allMatches', '/vm/lib/string_patch.dart'),
          ('_StringBase', 'splitMapJoin', '/vm/lib/string_patch.dart'),
          (
            '_StringBase',
            '_createStringFromIterable',
            '/vm/lib/string_patch.dart',
          ),
          ('_StringBase', 'replaceRange', '/vm/lib/string_patch.dart'),
          ('_StringBase', 'replaceAllMapped', '/vm/lib/string_patch.dart'),
          ('_IntegerImplementation', 'toRadixString', '/vm/lib/integers.dart'),
          ('_Smi', 'toString', '/vm/lib/integers.dart'),
          ('_Double', 'toString', '/vm/lib/double.dart'),
          ('_Double', 'toStringAsFixed', '/vm/lib/double.dart'),
          ('_Double', '_toStringAsFixed', '/sdk/patches/double.dart'),
          ('_GrowableList', 'add', '/vm/lib/growable_array.dart'),
          ('_GrowableList', 'addAll', '/vm/lib/growable_array.dart'),
          ('_GrowableList', '_grow', '/vm/lib/growable_array.dart'),
          ('_Array', 'toList', '/vm/lib/array.dart'),
        ]) {
          final member = core.element.getClass(type)!.getMethod(method)!;
          final body = core.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
          expect(
            member.formalParameters.any((p) => p.name == 'onError'),
            isFalse,
          );
        }
        final nativeParse = core.element
            .getClass('double')!
            .getMethod('_nativeParse')!;
        final declaration = core.getFragmentDeclaration(
          nativeParse.firstFragment,
        )!;
        expect(
          patches.origins[declaration.resolvedUnit!.uri]!.path,
          endsWith('/vm/lib/double_patch.dart'),
        );
        for (final (type, constructor, source) in [
          ('List', 'empty', '/sdk/patches/list.dart'),
          ('List', 'from', '/vm/lib/array_patch.dart'),
          ('List', 'of', '/vm/lib/array_patch.dart'),
          ('List', 'filled', '/vm/lib/array_patch.dart'),
          ('List', 'generate', '/vm/lib/array_patch.dart'),
          ('List', 'unmodifiable', '/vm/lib/array_patch.dart'),
          ('String', 'fromCharCode', '/vm/lib/string_patch.dart'),
          ('Map', 'new', '/vm_shared/lib/map_patch.dart'),
        ]) {
          final member = core.element
              .getClass(type)!
              .constructors
              .singleWhere((c) => c.name == constructor);
          expect(member.fragments, hasLength(2));
          final body = core.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
        }
        expect(
          core.element
              .getClass('List')!
              .getNamedConstructor('from')!
              .formalParameters
              .first
              .type
              .getDisplayString(),
          'Iterable<Object?>',
        );
        for (final name in ['_OneByteString', '_TwoByteString']) {
          final storage = core.element.getClass(name)!;
          final body = core.getFragmentDeclaration(storage.firstFragment)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith('/sdk/patches/string.dart'),
          );
          expect(storage.supertype!.element.name, '_StringBase');
        }
        final expando = core.element.getClass('Expando')!;
        final string = core.element.getClass('String')!;
        expect(string.getMethod('trim')!.isAbstract, isTrue);
        expect(string.getMethod('substring')!.isAbstract, isTrue);
        expect(string.getMethod('toString'), isNull);
        expect(string.getMethod('allMatches'), isNull);
        expect(expando.fragments, hasLength(2));
        expect(
          expando.fields.where((field) => field.name == 'name'),
          hasLength(1),
        );
        expect(
          expando.fields.map((field) => field.name),
          containsAll(['_data', '_used']),
        );
        final original = core.getFragmentDeclaration(
          expando.getMethod('toString')!.firstFragment,
        )!;
        expect(original.resolvedUnit!.uri.toString(), 'dart:core/weak.dart');
        expect(original.node.toSource(), contains(r'"Expando:$name"'));
        final ctor = expando.unnamedConstructor!;
        expect(ctor.isGenerative, isTrue);
        expect(ctor.fragments, hasLength(2));
        expect(
          ctor.formalParameters.single.computeConstantValue()!.isNull,
          isTrue,
        );
        expect(
          core.element.getClass('Object')!.unnamedConstructor!.isConst,
          isTrue,
        );
        expect(
          core.units.every(
            (unit) => unit.unit.featureSet.isEnabled(Feature.augmentations),
          ),
          isTrue,
        );
        expect(
          libraries.first.units.single.unit.featureSet.isEnabled(
            Feature.augmentations,
          ),
          isFalse,
        );
      });
    },
  );
  for (final (name, change, code)
      in <(String, String Function(String), String)>[
        (
          'parameter types',
          (source) => source.replaceFirst(
            'factory Finalizer(void Function(T) callback)',
            'factory Finalizer(void Function(int) callback)',
          ),
          'augmentation_formal_parameter_type_mismatch',
        ),
        (
          'return types',
          (source) => source.replaceFirst(
            'T? get target => _storage',
            'String? get target => "wrong"',
          ),
          'augmentation_return_type_mismatch',
        ),
        (
          'external return types',
          (source) => source.replaceFirst(
            'T? get target => _storage;',
            'external String? get target;',
          ),
          'augmentation_return_type_mismatch',
        ),
        (
          'unused bodies',
          (source) => '$source\nint _unused() => "wrong";',
          'return_of_invalid_type',
        ),
        (
          'extra public parameters',
          (source) => source.replaceFirst(
            'factory Finalizer(void Function(T) callback)',
            'factory Finalizer(void Function(T) callback, {int? unrelated})',
          ),
          'augmentation_named_formal_parameter_extra',
        ),
      ]) {
    test('SDK implementations cannot hide invalid $name', () async {
      await withImplementations((libraries, _) {
        expect([
          for (final library in libraries)
            for (final unit in library.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == .error)
                  diagnostic.diagnosticCode.lowerCaseName,
        ], contains(code));
      }, change: change);
    });
  }
  for (final patch in [
    'class PublicApi {}',
    'mixin PublicApi {}',
    'typedef PublicAlias = int;',
    'class _OneByteString {}',
    '@patch class String { @override int unrelated() => 0; }',
    '@patch class String { static String toString() => "wrong"; }',
    '@patch class Finalizer<T> extends Object {}',
    '@patch class Expando<T extends Object> { @patch String toString() => "overwritten"; }',
    '@patch class Error { @patch external static String safeToString(Object? object); }',
  ]) {
    test(
      'rejects changes outside the SDK implementation boundary: $patch',
      () async {
        await expectLater(
          withImplementations((_, _) {}, change: (source) => '$source\n$patch'),
          throwsFormatException,
        );
      },
    );
  }
}
