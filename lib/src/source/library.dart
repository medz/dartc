import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/line_info.dart';

import 'problem.dart';

/// One resolved file.
final class SourceUnit(
  final String path,
  final CompilationUnit ast,
  final LineInfo _lines,
) {
  /// A problem at [offset] characters into the file.
  SourceProblem problemAt(int offset, String message) {
    final at = _lines.getLocation(offset);
    return SourceProblem(path, at.lineNumber, at.columnNumber, message);
  }

  /// A problem at the start of [node].
  SourceProblem problem(AstNode node, String message) =>
      problemAt(node.offset, message);
}

/// The program's first library, free of static errors.
final class SourceLibrary(
  final LibraryElement element,
  Iterable<SourceUnit> units,
) {
  final List<SourceUnit> units = .unmodifiable(units);
}

/// Resolves the library at [path] against the Dart SDK at [sdk].
///
/// Throws [CompileFailure] if it, or any library it reaches outside the SDK,
/// has a static error.
Future<SourceLibrary> loadLibrary(String path, {required String sdk}) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw CompileFailure([SourceProblem(path, 1, 1, 'File not found.')]);
  }
  final resolved = file.resolveSymbolicLinksSync();
  final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  var libraries = await _resolveAll(resolved, sdk, files);
  // Comments may hide errors from the analyzer, but they are errors still.
  if (_disableIgnores(libraries, files)) {
    libraries = await _resolveAll(resolved, sdk, files);
  }
  final problems = [
    for (final library in libraries)
      for (final unit in library.units)
        for (final diagnostic in unit.diagnostics)
          if (diagnostic.severity == Severity.error)
            _unit(unit).problemAt(diagnostic.offset, diagnostic.message),
  ];
  if (problems.isNotEmpty) throw CompileFailure(problems);
  final first = libraries.first;
  return SourceLibrary(first.element, first.units.map(_unit));
}

SourceUnit _unit(ResolvedUnitResult result) =>
    SourceUnit(result.path, result.unit, result.lineInfo);

/// The library at [path], then every library it reaches outside the SDK.
Future<List<ResolvedLibraryResult>> _resolveAll(
  String path,
  String sdk,
  ResourceProvider files,
) async {
  final contexts = AnalysisContextCollection(
    includedPaths: [path],
    sdkPath: sdk,
    resourceProvider: files,
  );
  try {
    final session = contexts.contextFor(path).currentSession;
    final first = await session.getResolvedLibrary(path);
    if (first is! ResolvedLibraryResult) {
      throw CompileFailure([
        SourceProblem(path, 1, 1, 'Not a library that can be compiled.'),
      ]);
    }
    final results = [first];
    final seen = {first.element};
    for (var i = 0; i < results.length; i++) {
      final library = results[i].element;
      for (final next in [
        for (final fragment in library.fragments) ...fragment.importedLibraries,
        ...library.exportedLibraries,
      ]) {
        if (next.isInSdk || !seen.add(next)) continue;
        final result = await session.getResolvedLibraryByElement(next);
        if (result is! ResolvedLibraryResult) {
          throw StateError('Unresolved library ${next.uri}.');
        }
        results.add(result);
      }
    }
    return results;
  } finally {
    await contexts.dispose();
  }
}

/// Overlays every file having ignore comments with a copy where they say
/// something else of the same length. Returns whether there are any.
bool _disableIgnores(
  List<ResolvedLibraryResult> libraries,
  OverlayResourceProvider files,
) {
  var found = false;
  for (final unit in libraries.expand((library) => library.units)) {
    final text = StringBuffer();
    var copied = 0;
    Token? token = unit.unit.beginToken;
    while (token != null) {
      Token? comment = token.precedingComments;
      for (; comment != null; comment = comment.next) {
        if (!comment.lexeme.contains('ignore')) continue;
        text
          ..write(unit.content.substring(copied, comment.offset))
          ..write(comment.lexeme.replaceAll('ignore', 'IGNORE'));
        copied = comment.end;
      }
      token = token.isEof ? null : token.next;
    }
    if (copied == 0) continue;
    found = true;
    text.write(unit.content.substring(copied));
    files.setOverlay(unit.path, content: '$text', modificationStamp: 0);
  }
  return found;
}
