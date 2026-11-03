import 'dart:async';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

/// Resolved libraries checked in one SDK language context before any IR is built.
final class CheckedLibraries {
  final List<ResolvedLibraryResult> libraries;
  CheckedLibraries._(this.libraries);

  /// Resolves all paths in the first library's package context and keeps its
  /// analyzer session alive until [consume] has finished with the ASTs.
  static Future<T> read<T>(
    List<String> paths,
    FutureOr<T> Function(CheckedLibraries) consume,
  ) async {
    if (paths.isEmpty) throw ArgumentError('At least one library is required.');
    final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    final path = files.pathContext;
    final inputs = {
      for (final file in paths) path.normalize(path.absolute(file)),
    };
    if (inputs.length != paths.length) {
      throw ArgumentError('Duplicate input library.');
    }
    for (final file in inputs) {
      // Editor suppressions must not erase a language error before lowering.
      files.setOverlay(
        path.join(path.dirname(file), 'analysis_options.yaml'),
        content: 'analyzer:\n  cannot-ignore: [error]\n',
        modificationStamp: 0,
      );
    }
    final contexts = AnalysisContextCollection(
      includedPaths: inputs.toList(),
      resourceProvider: files,
    );
    try {
      final session = contexts.contextFor(inputs.first).currentSession;
      final libraries = <ResolvedLibraryResult>[];
      for (final file in inputs) {
        final result = await session.getResolvedLibrary(file);
        if (result is! ResolvedLibraryResult) {
          throw FormatException('Expected a Dart library: $file');
        }
        for (final unit in result.units) {
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
        libraries.add(result);
      }
      return await consume(CheckedLibraries._(List.unmodifiable(libraries)));
    } finally {
      await contexts.dispose();
    }
  }
}
