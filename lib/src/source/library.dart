import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';

import 'analysis.dart';
import 'corrections.dart';
import 'problem.dart';
import 'sdk.dart';

/// One resolved file.
final class SourceUnit(
  final String path,
  final CompilationUnit ast,
  final CorrectedText _content,
) {
  late final _lines = LineInfo.fromContent(_content.original);

  /// The text of [node] in the file.
  String textOf(AstNode node) => _content.original.substring(
    _content.originalOffset(node.offset),
    _content.originalOffset(node.end),
  );

  /// A problem at [offset] characters into the text that was resolved.
  SourceProblem problemAt(int offset, String message) {
    final at = _lines.getLocation(_content.originalOffset(offset));
    return SourceProblem(path, at.lineNumber, at.columnNumber, message);
  }

  /// A problem at the start of [node].
  SourceProblem problem(AstNode node, String message) =>
      problemAt(node.offset, message);
}

/// One resolved library.
final class SourceLibrary(
  final LibraryElement element,
  Iterable<SourceUnit> units,
) {
  final List<SourceUnit> units = .unmodifiable(units);
}

/// A program free of static errors.
///
/// [libraries] starts with the one holding `main` and includes every library
/// reached outside the SDK. Of the SDK, [sdk] has those that can be compiled
/// and are reached, and the runtime.
final class SourceProgram(
  Iterable<SourceLibrary> libraries,
  Iterable<SourceLibrary> sdk,
) {
  final List<SourceLibrary> libraries = .unmodifiable(libraries);
  final List<SourceLibrary> sdk = .unmodifiable(sdk);
  SourceLibrary get main => libraries.first;
}

/// Resolves the program at [path] against the libraries of [sdk].
///
/// Throws [CompileFailure] if it, or any library it reaches outside the SDK,
/// has a static error.
Future<SourceProgram> loadProgram(
  String path, {
  required SdkSources sdk,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw CompileFailure([SourceProblem(path, 1, 1, 'File not found.')]);
  }
  final resolved = file.resolveSymbolicLinksSync();
  final shared = Analysis.shared(resolved, sdk);
  // Until it is known that there are no errors.
  shared.release();
  var libraries = await shared.resolve(resolved);
  final isFirst = shared.isFirstToRead(libraries.own);
  if (!isFirst) libraries = await Analysis(resolved, sdk).resolve(resolved);
  // Some constants have to be analyzed as other text.
  final corrected = {
    for (final unit in libraries.own.expand((library) => library.units))
      unit.path: ?correctionsOf(unit.unit, unit.content),
  };
  if (corrected.isNotEmpty) {
    final replaced = corrected.map((path, text) => MapEntry(path, text.text));
    final own = Analysis(resolved, sdk, replaced: replaced);
    libraries = await own.resolve(resolved);
  }
  SourceUnit unitOf(ResolvedUnitResult result) => SourceUnit(
    result.path,
    result.unit,
    corrected[result.path] ?? CorrectedText(result.content, const []),
  );
  final problems = [
    for (final library in libraries.own)
      for (final unit in library.units)
        for (final diagnostic in unit.diagnostics)
          if (diagnostic.severity == Severity.error)
            unitOf(unit).problemAt(diagnostic.offset, diagnostic.message),
  ];
  if (problems.isNotEmpty) throw CompileFailure(problems);
  if (isFirst) shared.share();
  SourceLibrary library(ResolvedLibraryResult result) =>
      SourceLibrary(result.element, result.units.map(unitOf));
  return SourceProgram(libraries.own.map(library), libraries.sdk.map(library));
}
