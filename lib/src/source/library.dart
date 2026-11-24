import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/line_info.dart';
// Only this can be told about the environment.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart'
    show AnalysisContextCollectionImpl;

import 'problem.dart';
import 'sdk.dart';

/// One resolved file.
final class SourceUnit(
  final String path,
  final CompilationUnit ast,
  final String content,
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
/// reached outside the SDK. Of the SDK, [sdk] has those that can be compiled.
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
  final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
  sdk.install(files);
  var (libraries, core) = await _resolveAll(resolved, sdk, files);
  if (_renameUnknown(libraries, files)) {
    (libraries, core) = await _resolveAll(resolved, sdk, files);
  }
  final problems = [
    for (final library in libraries)
      for (final unit in library.units)
        for (final diagnostic in unit.diagnostics)
          if (diagnostic.severity == Severity.error)
            _unit(unit).problemAt(diagnostic.offset, diagnostic.message),
  ];
  if (problems.isNotEmpty) throw CompileFailure(problems);
  return SourceProgram(libraries.map(_library), core.map(_library));
}

SourceLibrary _library(ResolvedLibraryResult result) =>
    SourceLibrary(result.element, result.units.map(_unit));

SourceUnit _unit(ResolvedUnitResult result) =>
    SourceUnit(result.path, result.unit, result.content, result.lineInfo);

/// The library at [path], then every library it reaches outside the SDK. Also
/// the libraries of the SDK that can be compiled.
Future<(List<ResolvedLibraryResult>, List<ResolvedLibraryResult>)> _resolveAll(
  String path,
  SdkSources sdk,
  OverlayResourceProvider files,
) async {
  // Neither comments nor the options of a project hide errors.
  final options = '${File(path).parent.path}/.dartc_options.yaml';
  files.setOverlay(
    options,
    content: 'analyzer:\n  cannot-ignore: [error]\n',
    modificationStamp: 0,
  );
  final contexts = AnalysisContextCollectionImpl(
    includedPaths: [path],
    sdkPath: sdk.root,
    resourceProvider: files,
    optionsFile: options,
    declaredVariables: sdk.environment,
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
        results.add(await _resolve(session, next));
      }
    }
    final core = <ResolvedLibraryResult>[];
    for (final uri in sdk.libraries) {
      final found = await session.getLibraryByUri(uri);
      if (found is! LibraryElementResult) throw StateError('No library $uri.');
      core.add(await _resolve(session, found.element));
    }
    return (results, core);
  } finally {
    await contexts.dispose();
  }
}

Future<ResolvedLibraryResult> _resolve(
  AnalysisSession session,
  LibraryElement library,
) async {
  final result = await session.getResolvedLibraryByElement(library);
  return result is ResolvedLibraryResult
      ? result
      : throw StateError('Unresolved library ${library.uri}.');
}

/// What the analyzer takes to be unknown, though it is false for programs that
/// are not compiled to JavaScript.
final _unknown = RegExp(
  r'''fromEnvironment\(\s*['"]dart\.library\.js_(?:interop|util)['"]''',
);

/// Overlays every file that asks for what is [_unknown] with a copy asking for
/// something of the same length. Returns whether there are any.
bool _renameUnknown(
  List<ResolvedLibraryResult> libraries,
  OverlayResourceProvider files,
) {
  var found = false;
  for (final unit in libraries.expand((library) => library.units)) {
    if (!unit.content.contains(_unknown)) continue;
    found = true;
    files.setOverlay(
      unit.path,
      content: unit.content.replaceAllMapped(
        _unknown,
        (match) => match[0]!.replaceFirst('dart.library', 'none.library'),
      ),
      modificationStamp: 0,
    );
  }
  return found;
}
