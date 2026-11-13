import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
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
  String changePath = 'core.dart',
}) async {
  final archive = await SdkSources.load();
  const root = '/__dartc__', runtime = '$root/sdk/patches';
  final files = OverlayResourceProvider(
    SourceFiles(archive, root, extraSources: archive),
  );
  if (change != null) {
    final path = '$runtime/$changePath';
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
              'dart:math',
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
  test('source positions map patched views and library insertions back to originals', () async {
    final sources = await SdkSources.load();
    await withImplementations((libraries, patches) {
      final math = libraries.singleWhere(
        (library) => library.element.uri.toString() == 'dart:math',
      );
      final vm = libraries.singleWhere(
        (library) => library.element.uri.toString() == 'dart:_vm',
      );
      final squareRoot = math.getFragmentDeclaration(
        math.element.getTopLevelFunction('sqrt')!.fragments.last,
      )!;
      final seed = math.getFragmentDeclaration(
        math.element
            .getClass('_Random')!
            .getMethod('_initialSeed')!
            .fragments
            .last,
      )!;
      final value = vm.getFragmentDeclaration(
        vm.element
            .getClass('FinalThreadLocal')!
            .getGetter('value')!
            .fragments
            .last,
      )!;
      for (final (declaration, path, marker) in [
        (
          squareRoot,
          'sdk/std/lib/_internal/vm/lib/math_patch.dart',
          '=> _sqrt(x.toDouble())',
        ),
        (seed, 'sdk/patches/math.dart', '=>\n      _setupSeed('),
        (value, 'sdk/std/lib/_vm/_vm.dart', '{\n    if (!variable.hasValue)'),
      ]) {
        final body = switch (declaration.node) {
          FunctionDeclaration(:final functionExpression) =>
            functionExpression.body,
          MethodDeclaration(:final body) => body,
          _ => throw StateError('Expected executable declaration'),
        };
        final original = utf8.decode(sources.read(path));
        final offset = original.lastIndexOf(marker);
        expect(offset, greaterThanOrEqualTo(0));
        final location = LineInfo.fromContent(original).getLocation(offset);
        expect(
          patches.sourceLocation(declaration.resolvedUnit!.uri, body.offset),
          (
            uri: Uri.file('/__dartc__/$path'),
            line: location.lineNumber,
            column: location.columnNumber,
          ),
        );
      }
    });
  });
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
        expect(ffi.element.getClass('Abi')!.isFinal, isFalse);
        final dynamicLibrary = ffi.element.getClass('DynamicLibrary')!;
        expect(dynamicLibrary.getMethod('getHandle'), isNull);
        final equality = ffi.getFragmentDeclaration(
          dynamicLibrary.getMethod('==')!.fragments.last,
        )!;
        expect(
          patches.origins[equality.resolvedUnit!.uri]!.path,
          endsWith('/vm/lib/ffi_dynamic_library_patch.dart'),
        );
        final close = ffi.getFragmentDeclaration(
          ffi.element
              .getClass('_NativeCallableBase')!
              .getMethod('close')!
              .fragments
              .last,
        )!;
        expect(
          patches.origins[close.resolvedUnit!.uri]!.path,
          endsWith('/vm/lib/ffi_patch.dart'),
        );
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
        final then = async.element.getClass('_Future')!.getMethod('then')!;
        expect(then.fragments, hasLength(1));
        expect(
          async
              .getFragmentDeclaration(then.firstFragment)!
              .resolvedUnit!
              .uri
              .toString(),
          'dart:async/future_impl.dart',
        );
        final math = libraries.singleWhere(
          (library) => library.element.uri == Uri.parse('dart:math'),
        );
        final squareRoot = math.getFragmentDeclaration(
          math.element.getTopLevelFunction('sqrt')!.fragments.last,
        )!;
        expect(
          patches.origins[squareRoot.resolvedUnit!.uri]!.path,
          endsWith('/vm/lib/math_patch.dart'),
        );
        expect(math.element.getTopLevelFunction('_sqrt')!.isExternal, isTrue);
        for (final (name, source) in [
          ('pow', '/vm/lib/math_patch.dart'),
          ('_intPow', '/vm/lib/math_patch.dart'),
          ('sin', '/vm/lib/math_patch.dart'),
          ('_doublePow', '/sdk/patches/math.dart'),
        ]) {
          final function = math.element.getTopLevelFunction(name)!;
          final body = math.getFragmentDeclaration(function.fragments.last)!;
          expect(function.isExternal, isFalse);
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
        }
        for (final (type, method, source) in [
          ('_Random', 'nextInt', '/vm/lib/math_patch.dart'),
          ('_Random', '_initialSeed', '/sdk/patches/math.dart'),
          ('_SecureRandom', 'nextInt', '/vm/lib/math_patch.dart'),
          ('_SecureRandom', '_getBytes', '/sdk/patches/math.dart'),
        ]) {
          final member = math.element.getClass(type)!.getMethod(method)!;
          final body = math.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
        }
        final core = libraries.singleWhere(
          (library) => library.element.isDartCore,
        );
        for (final (type, method, source) in [
          ('_StringBase', '*', '/vm/lib/string_patch.dart'),
          ('_StringBase', 'padLeft', '/sdk/patches/string.dart'),
          ('_Double', 'remainder', '/vm/lib/double.dart'),
          ('_Double', '_remainder', '/sdk/patches/double.dart'),
          ('Stopwatch', '_now', '/sdk/patches/core.dart'),
          ('DateTime', 'compareTo', '/vm_shared/lib/date_patch.dart'),
          ('RegExp', 'escape', '/vm/lib/regexp_patch.dart'),
        ]) {
          final member = core.element.getClass(type)!.getMethod(method)!;
          final body = core.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
        }
        for (final (type, getter, source) in [
          (
            '_BigIntImpl',
            '_cachedDivRemResult',
            '/vm/lib/bigint_patch_patch.dart',
          ),
          ('Stopwatch', 'elapsedMicroseconds', '/vm/lib/stopwatch_patch.dart'),
        ]) {
          final member = core.element.getClass(type)!.getGetter(getter)!;
          final body = core.getFragmentDeclaration(member.fragments.last)!;
          expect(
            patches.origins[body.resolvedUnit!.uri]!.path,
            endsWith(source),
          );
        }
        final from = core.element
            .getClass('List')!
            .getNamedConstructor('from')!;
        expect(from.fragments, hasLength(2));
        final fromBody = core.getFragmentDeclaration(from.fragments.last)!;
        expect(
          patches.origins[fromBody.resolvedUnit!.uri]!.path,
          endsWith('/vm/lib/array_patch.dart'),
        );
        expect(
          from.formalParameters.first.type.getDisplayString(),
          'Iterable<Object?>',
        );
        final expando = core.element.getClass('Expando')!;
        final string = core.element.getClass('String')!;
        expect(string.getMethod('trim')!.isAbstract, isTrue);
        expect(expando.fragments, hasLength(2));
        expect(
          expando.fields.where((field) => field.name == 'name'),
          hasLength(1),
        );
        final privateStorage = expando.getField('_data')!;
        expect(privateStorage.isPrivate, isTrue);
        expect(privateStorage.library, same(core.element));
        final original = core.getFragmentDeclaration(
          expando.getMethod('toString')!.firstFragment,
        )!;
        expect(original.resolvedUnit!.uri.toString(), 'dart:core/weak.dart');
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
          'class modifiers',
          (source) =>
              source.replaceFirst('class Object {', 'final class Object {'),
          'augmentation_modifier_extra',
        ),
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
  test('internal library bodies also require a concrete adaptation', () async {
    await expectLater(
      withImplementations(
        (_, _) {},
        changePath: 'internal.dart',
        change: (source) =>
            '$source\n@patch class Symbol { @patch static String getName(Symbol symbol) => "overwritten"; }',
      ),
      throwsFormatException,
    );
  });
  for (final patch in [
    'class PublicApi {}',
    'extension PublicApi on String {}',
    'mixin PublicApi {}',
    'typedef PublicAlias = int;',
    'class _OneByteString {}',
    '@patch class String { @override int unrelated() => 0; }',
    '@patch class String { static String toString() => "wrong"; }',
    '@patch class Finalizer<T> extends Object {}',
    '@patch class Expando<T extends Object> { @patch String toString() => "overwritten"; }',
    '@patch class Error { @patch external static String safeToString(Object? object); }',
    '@patch class _StringBase { @patch String trim() => "overwritten"; }',
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

  test('target patches cannot introduce public native helpers', () async {
    await expectLater(
      withImplementations(
        (_, _) {},
        changePath: 'dynamic_library.dart',
        change: (source) =>
            '$source\n@patch class DynamicLibrary { external int extra(); }',
      ),
      throwsFormatException,
    );
  });
}
