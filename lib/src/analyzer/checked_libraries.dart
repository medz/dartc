import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
// A single options override also protects transitive dependency diagnostics.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:dartc/sdk.dart';

/// A batch of Dart libraries whose units have passed static error checks.
///
/// Access the analyzer results during the callback to [read].
final class CheckedLibraries._(Iterable<ResolvedLibraryResult> input) {
  /// The resolved libraries in the order of the input paths.
  final List<ResolvedLibraryResult> libraries = .unmodifiable(input);

  this {
    if (libraries.isEmpty) {
      throw ArgumentError('At least one library is required.');
    }
    final session = libraries.first.session;
    final uris = <Uri>{};
    for (final library in libraries) {
      if (!identical(library.session, session) ||
          !uris.add(library.element.uri)) {
        throw ArgumentError('Expected distinct libraries from one session.');
      }
      for (final unit in library.units) {
        for (final error in unit.diagnostics) {
          if (error.severity == .error) {
            throw FormatException(
              '${unit.uri}: ${error.message}',
              unit.content,
              error.offset,
            );
          }
        }
      }
    }
  }

  /// Resolves [paths] and returns the result of [consume].
  ///
  /// Paths use the first library's package context. Every unit of every input
  /// library is checked before [consume] runs, including parts and unused
  /// declarations. Source and editor suppressions cannot hide language errors.
  /// The analysis session remains open until [consume] completes.
  /// With [includeDependencies], also checks and supplies imported and exported
  /// non-SDK libraries from the same session.
  ///
  /// Throws [ArgumentError] for an empty list or duplicate normalized paths.
  /// Throws [FormatException] for a non-library input or a reported language
  /// error.
  static Future<T> read<T>(
    List<String> paths,
    FutureOr<T> Function(CheckedLibraries) consume, {
    DartSdk? sdk,
    bool includeDependencies = false,
  }) async {
    if (paths.isEmpty) throw ArgumentError('At least one library is required.');
    final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    final path = files.pathContext;
    final inputs = {
      for (final file in paths) path.normalize(path.absolute(file)),
    };
    if (inputs.length != paths.length) {
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
    final contexts = AnalysisContextCollectionImpl(
      includedPaths: inputs.toList(),
      resourceProvider: files,
      sdkPath: sdk?.directory.path,
      optionsFile: options,
    );
    try {
      final session = contexts.contextFor(inputs.first).currentSession;
      final libraries = <ResolvedLibraryResult>[];
      final queue = inputs.toList();
      for (var i = 0; i < queue.length; i++) {
        final file = queue[i];
        final result = await session.getResolvedLibrary(file);
        if (result is! ResolvedLibraryResult) {
          throw FormatException('Expected a Dart library: $file');
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
      return await consume(CheckedLibraries._(libraries));
    } finally {
      await contexts.dispose();
    }
  }
}
