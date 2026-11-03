import 'dart:async';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

/// A batch of Dart libraries whose units have passed static error checks.
///
/// Access the analyzer results during the callback to [read].
final class CheckedLibraries._(
  /// The resolved libraries in the order of the input paths.
  final List<ResolvedLibraryResult> libraries,
) {
  /// Resolves [paths] and returns the result of [consume].
  ///
  /// Paths use the first library's package context. Every unit of every input
  /// library is checked before [consume] runs, including parts and unused
  /// declarations. Source and editor suppressions cannot hide language errors.
  /// The analysis session remains open until [consume] completes.
  ///
  /// Throws [ArgumentError] for an empty list or duplicate normalized paths.
  /// Throws [FormatException] for a non-library input or a reported language
  /// error.
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
      return await consume(CheckedLibraries._(.unmodifiable(libraries)));
    } finally {
      await contexts.dispose();
    }
  }
}
