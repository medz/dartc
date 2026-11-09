import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
// A single options override also protects transitive dependency diagnostics.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:dartc/sdk.dart';

import '../constant_evaluation.dart';

/// Owns the analysis resources and resolved snapshot of one library batch.
///
/// Call [close] after consuming [resolve], or use [use] for scoped access.
final class AnalysisSession(
  Iterable<String> paths, {
  final DartSdk? sdk,
  final bool includeDependencies = false,
}) {
  final List<String> _paths = .unmodifiable(paths);
  AnalysisContextCollectionImpl? _contexts;
  Future<CheckedLibraries>? _resolution;
  Future<void>? _closing;
  bool _using = false;

  /// Resolves and checks this batch, sharing one in-flight result per session.
  ///
  /// The first path supplies the package context. Parts and unused declarations
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
      await _resolution;
    } catch (_) {
      // Resolution reports its error; disposal must still finish.
    }
    await _contexts?.dispose();
  }

  Future<CheckedLibraries> _resolve() async {
    if (_paths.isEmpty) {
      throw ArgumentError('At least one library is required.');
    }
    final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    final path = files.pathContext;
    final inputs = {
      for (final file in _paths) path.normalize(path.absolute(file)),
    };
    if (inputs.length != _paths.length) {
      throw ArgumentError('Duplicate input library.');
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
      sdkPath: sdk?.directory.path,
      optionsFile: options,
    );
    final session = contexts.contextFor(inputs.first).currentSession;
    final libraries = <ResolvedLibraryResult>[];
    final queue = inputs.toList();
    for (var i = 0; i < queue.length; i++) {
      final result = await session.getResolvedLibrary(queue[i]);
      if (result is! ResolvedLibraryResult) {
        throw FormatException('Expected a Dart library: ${queue[i]}');
      }
      libraries.add(result);
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
    return CheckedLibraries._(libraries, _checkOpen);
  }
}

/// Libraries whose units have passed static checks in their owning session.
final class CheckedLibraries._(
  Iterable<ResolvedLibraryResult> input,
  void Function() checkOpen,
) {
  final List<ResolvedLibraryResult> _libraries = .unmodifiable(input);
  final void Function() _checkOpen = checkOpen;
  final _constants = ConstantEvaluation();

  /// The resolved libraries, accessible until their session is closed.
  ///
  /// Analyzer objects retain their original diagnostics and constant values.
  /// The session's constant checks and IR translation use corrected values.
  List<ResolvedLibraryResult> get libraries {
    _checkOpen();
    return _libraries;
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
extension CheckedConstants on CheckedLibraries {
  ConstantEvaluation get constants {
    _checkOpen();
    return _constants;
  }
}
