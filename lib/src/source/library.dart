import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';

import 'analysis.dart';
import 'corrected_text.dart';
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

  /// The field that preserves the value of [element]'s own `_name` field.
  String? enumNameField(EnumElement element) =>
      _content.enumNameFields[element.name];

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
  var analysis = Analysis.of(resolved, sdk);
  var isRight = false;
  Future<ResolvedLibraries> resolveAlone([
    Map<String, String> replaced = const {},
  ]) async {
    await analysis.close();
    analysis = Analysis(resolved, sdk, replaced: replaced);
    return (await analysis.resolve(resolved))!;
  }

  try {
    var libraries = await analysis.resolve(resolved) ?? await resolveAlone();
    // Some constants have to be analyzed as other text.
    final corrected = {
      for (final library in libraries.own)
        ...correctionsOf(library.units, sdk.environment),
    };
    if (corrected.isNotEmpty) {
      libraries = await resolveAlone({
        for (final MapEntry(:key, :value) in corrected.entries) key: value.text,
      });
    }
    final program = _checked(libraries, corrected);
    isRight = true;
    return program;
  } finally {
    await (isRight ? analysis.keep() : analysis.close());
  }
}

/// The program that [libraries] are, some of whose texts were [corrected], if
/// they have no errors.
SourceProgram _checked(
  ResolvedLibraries libraries,
  Map<String, CorrectedText> corrected,
) {
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
  SourceLibrary library(ResolvedLibraryResult result) =>
      SourceLibrary(result.element, result.units.map(unitOf));
  return SourceProgram(libraries.own.map(library), libraries.sdk.map(library));
}
