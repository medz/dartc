import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
// A single options override also protects transitive dependency diagnostics.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:dartc/sdk.dart';

import '../analyzer_metadata.dart';
import '../constant_evaluation.dart';
import 'source_files.dart';
import 'sdk_patches.dart';

/// Owns the analysis resources and resolved snapshot of one library batch.
///
/// Call [close] after consuming [resolve], or use [use] for scoped access.
/// [sdk] supplies fixed source resources; when omitted, the dartc package's
/// resources are used. No installed SDK is discovered.
/// Additional source-resource libraries join the same checked batch and package
/// context; [CheckedLibraries.resources] retains their archive identities.
final class AnalysisSession(
  Iterable<String> paths, {
  final bool includeDependencies = false,
  final DartSdk? sdk,

  /// Additional private sources, separate from the standard library selection.
  final SourceArchive? sourceArchive,

  /// Archive paths of libraries to check alongside the file inputs.
  Iterable<String> resources = const [],
}) {
  final List<String> _paths = .unmodifiable(paths);
  final List<String> _resources = .unmodifiable(resources);
  AnalysisContextCollectionImpl? _contexts;
  Future<CheckedLibraries>? _resolution;
  Future<void>? _closing;
  bool _using = false;

  /// Resolves and checks this batch, sharing one in-flight result per session.
  ///
  /// The first path supplies the package context. A resource-only batch has no
  /// user package context. Parts and unused declarations
  /// are checked; source suppressions cannot hide static errors. When
  /// [includeDependencies] is enabled, non-SDK imports and exports are included.
  /// Throws [StateError] after closing, [ArgumentError] for invalid input paths,
  /// and [FormatException] for static errors or non-library inputs.
  Future<CheckedLibraries> resolve() {
    _checkOpen();
    return _resolution ??= _resolve();
  }

  /// Consumes the checked snapshot and closes the session even on failure.
  ///
  /// Scoped consumers cannot overlap. Results must not retain analyzer objects.
  Future<T> use<T>(FutureOr<T> Function(CheckedLibraries) consume) async {
    _checkOpen();
    if (_using) throw StateError('An analysis consumer is already active.');
    _using = true;
    try {
      return await consume(await resolve());
    } finally {
      await close();
    }
  }

  /// Waits for pending resolution and disposes the session exactly once.
  Future<void> close() => _closing ??= _close();

  void _checkOpen() {
    if (_closing != null) throw StateError('The analysis session is closed.');
  }

  Future<void> _close() async {
    try {
      final input = await _resolution;
      if (input != null) await Future.wait(input._dependencies.values);
    } catch (_) {
      // Resolution reports its error; disposal must still finish.
    }
    await _contexts?.dispose();
  }

  Future<CheckedLibraries> _resolve() async {
    if (_paths.isEmpty && _resources.isEmpty) {
      throw ArgumentError('At least one library is required.');
    }
    final path = PhysicalResourceProvider.INSTANCE.pathContext;
    final inputs = {
      for (final file in _paths) path.normalize(path.absolute(file)),
    };
    if (inputs.length != _paths.length) {
      throw ArgumentError('Duplicate input library.');
    }
    final sources = sdk ?? await DartSdk.load();
    final root = path.join(
      path.rootPrefix(inputs.firstOrNull ?? path.current),
      '__dartc__',
    );
    for (final name in _resources) {
      if (sourceArchive?.contains(name) != true) {
        throw ArgumentError('Source resource unavailable: $name');
      }
      inputs.add(path.join(root, name));
    }
    final files = OverlayResourceProvider(
      SourceFiles(sources.sources, root, extraSources: sourceArchive),
    );
    final sdkPath = path.join(root, 'sdk');
    if (sourceArchive?.contains('dartc/src/runtime/patches/core.dart') ==
        true) {
      SdkPatches(files).apply(
        path.join(sdkPath, 'lib/core/core.dart'),
        path.join(sdkPath, 'lib/core/weak.dart'),
        path.join(root, 'dartc/src/runtime/patches/core.dart'),
      );
      SdkPatches(files).apply(
        path.join(sdkPath, 'lib/async/async.dart'),
        path.join(sdkPath, 'lib/async/schedule_microtask.dart'),
        path.join(root, 'dartc/src/runtime/patches/async.dart'),
      );
      SdkPatches(files).apply(
        path.join(sdkPath, 'lib/internal/internal.dart'),
        path.join(sdkPath, 'lib/internal/print.dart'),
        path.join(root, 'dartc/src/runtime/patches/print.dart'),
      );
      SdkPatches(files).apply(
        path.join(sdkPath, 'lib/async/async.dart'),
        path.join(sdkPath, 'lib/async/timer.dart'),
        path.join(root, 'dartc/src/runtime/patches/timer.dart'),
      );
      SdkPatches(files).apply(
        path.join(sdkPath, 'lib/collection/collection.dart'),
        path.join(sdkPath, 'lib/collection/hash_map.dart'),
        path.join(root, 'dartc/src/runtime/patches/hash_map.dart'),
      );
    }
    final options = path.join(
      path.dirname(inputs.first),
      '.dartc-analysis.yaml',
    );
    files.setOverlay(
      options,
      content: 'analyzer:\n  cannot-ignore: [error]\n',
      modificationStamp: 0,
    );
    final contexts = _contexts = AnalysisContextCollectionImpl(
      includedPaths: inputs.toList(),
      resourceProvider: files,
      sdkPath: sdkPath,
      optionsFile: options,
    );
    final session = contexts.contextFor(inputs.first).currentSession;
    final libraries = <ResolvedLibraryResult>[];
    final resources = <String, ResolvedLibraryResult>{};
    final queue = inputs.toList();
    for (var i = 0; i < queue.length; i++) {
      final result = await session.getResolvedLibrary(queue[i]);
      if (result is! ResolvedLibraryResult) {
        throw FormatException('Expected a Dart library: ${queue[i]}');
      }
      libraries.add(result);
      if (path.isWithin(root, queue[i])) {
        final name = path
            .relative(queue[i], from: root)
            .replaceAll(path.separator, '/');
        if (sourceArchive?.contains(name) == true) resources[name] = result;
      }
      if (includeDependencies) {
        for (final dependency in [
          for (final fragment in result.element.fragments)
            ...fragment.importedLibraries,
          ...result.element.exportedLibraries,
        ]) {
          if (!dependency.isInSdk) {
            final path = dependency.firstFragment.source.fullName;
            if (inputs.add(path)) queue.add(path);
          }
        }
      }
    }
    return CheckedLibraries._(
      libraries,
      resources,
      sourceArchive?.contains('dartc/src/runtime/contracts.dart') == true
          ? path.toUri(path.join(root, 'dartc/src/runtime/contracts.dart'))
          : null,
      _checkOpen,
    );
  }
}

/// Libraries whose units have passed static checks in their owning session.
final class CheckedLibraries._(
  Iterable<ResolvedLibraryResult> input,
  Map<String, ResolvedLibraryResult> resources,
  final Uri? _runtimeContracts,
  void Function() checkOpen,
) {
  final List<ResolvedLibraryResult> _libraries = .unmodifiable(input);
  final Map<String, ResolvedLibraryResult> _resources = .unmodifiable(
    resources,
  );
  final void Function() _checkOpen = checkOpen;
  final _constants = ConstantEvaluation();
  final _dependencies = <LibraryElement, Future<ResolvedLibraryResult>>{};

  /// The input batch's resolved libraries, accessible until the session closes.
  ///
  /// Analyzer objects retain their original diagnostics and constant values.
  /// The session's constant checks and IR translation use corrected values.
  List<ResolvedLibraryResult> get libraries {
    _checkOpen();
    return _libraries;
  }

  /// Checked source-resource libraries, keyed by their archive paths.
  Map<String, ResolvedLibraryResult> get resources {
    _checkOpen();
    return _resources;
  }

  /// Evaluates an annotation using this session's checked constant semantics.
  DartObject? annotationValue(ResolvedUnitResult unit, Annotation annotation) {
    _checkOpen();
    if (!identical(unit.session, _libraries.first.session) ||
        !identical(annotation.root, unit.unit)) {
      throw ArgumentError('Annotation does not belong to this resolved unit.');
    }
    return _constants.annotation(unit, annotation);
  }

  this {
    if (_libraries.isEmpty) {
      throw ArgumentError('At least one library is required.');
    }
    final session = _libraries.first.session;
    final uris = <Uri>{};
    for (final library in _libraries) {
      if (!identical(library.session, session) ||
          !uris.add(library.element.uri)) {
        throw ArgumentError('Expected distinct libraries from one session.');
      }
      for (final unit in library.units) {
        _constants.check(unit);
      }
    }
  }
}

// Internal handoff; this extension is not exported by frontend.dart.
extension CheckedSources on CheckedLibraries {
  Uri? get runtimeContracts => _runtimeContracts;

  ConstantEvaluation get constants {
    _checkOpen();
    return _constants;
  }

  /// Resolves a referenced library and checks every unit before lowering it.
  Future<ResolvedLibraryResult> resolveLibrary(LibraryElement element) {
    _checkOpen();
    for (final library in _libraries) {
      if (identical(library.element, element)) return Future.value(library);
    }
    return _dependencies.putIfAbsent(element, () async {
      prepareSdkLibrary(element);
      final result = await _libraries.first.session.getResolvedLibraryByElement(
        element,
      );
      if (result is! ResolvedLibraryResult) {
        throw FormatException('Expected a Dart library: ${element.uri}');
      }
      for (final unit in result.units) {
        _constants.check(unit);
      }
      return result;
    });
  }
}
