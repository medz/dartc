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
  final archive = await SourceArchive.load();
  const root = '/__dartc__', runtime = '$root/dartc/src/runtime/patches';
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
  final patches = SdkPatches(files)..install('$root/sdk', runtime);
  final input = File('test/compiler/fixtures/expandos.dart').absolute.path;
  final contexts = AnalysisContextCollectionImpl(
    includedPaths: [input],
    resourceProvider: files,
    sdkPath: '$root/sdk',
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
        for (final name in ['_HashMap', '_HashSet', '_CustomHashMap']) {
          final source = collection.getFragmentDeclaration(
            collection.element.getClass(name)!.firstFragment,
          )!;
          expect(
            patches.origins[source.resolvedUnit!.uri]!.path,
            endsWith('/vm_shared/lib/collection_patch.dart'),
          );
        }
        final core = libraries.singleWhere(
          (library) => library.element.isDartCore,
        );
        for (final (type, constructor, source) in [
          ('List', 'empty', 'list.dart'),
          ('String', 'fromCharCode', 'string.dart'),
          ('Map', 'new', 'core.dart'),
        ]) {
          final member = core.element
              .getClass(type)!
              .constructors
              .singleWhere((c) => c.name == constructor);
          expect(member.fragments, hasLength(2));
          final body = core.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith('/runtime/patches/$source'),
          );
        }
        final expando = core.element.getClass('Expando')!;
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
          'unused bodies',
          (source) => '$source\nint _unused() => "wrong";',
          'return_of_invalid_type',
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
    '@patch class Finalizer<T> extends Object {}',
    '@patch class Expando<T extends Object> { @patch String toString() => "overwritten"; }',
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
