part of 'parser.dart';

/// Parses a source file into ordered directives and declarations.
///
/// The unit spans the whole source, including comments and whitespace. Imports
/// remain written URIs; parsing does not load dependencies or bind names.
/// Invalid or incomplete members produce diagnostics. Check
/// [ParseResult.hasErrors] before treating a unit as valid syntax.
ParseResult<CompilationUnit> parseCompilationUnit(
  ScanResult input, {
  LanguageVersion languageVersion = LanguageVersion.current,
}) {
  final parser = _Parser(input, languageVersion: languageVersion);
  final node = _readUnit(parser);
  return parser.finishResult(node);
}

/// Incremental parsing of a previously parsed compilation unit.
extension CompilationUnitParsing on ParseResult<CompilationUnit> {
  /// Parses [source], reusing unchanged syntax when the file and version match.
  ///
  /// Defaults to the previous language version. The result belongs to [source],
  /// even when its text is unchanged. Errors have the same recovery and
  /// diagnostics as a fresh parse.
  ParseResult<CompilationUnit> reparse(
    SourceFile source, {
    LanguageVersion? languageVersion,
  }) {
    final version = languageVersion ?? this.languageVersion;
    if (version == this.languageVersion) {
      final result = tryReparse(source);
      if (result != null) return result;
    }
    return parseCompilationUnit(
      scan(source, comments: .leading),
      languageVersion: version,
    );
  }

  /// Reuses a clean unit when the edit preserves its header and parser context.
  ///
  /// Returns `null` when a fresh scan is needed. A project loader can then
  /// read version comments from that scan before choosing the language version.
  ParseResult<CompilationUnit>? tryReparse(SourceFile source) {
    if (diagnostics.isNotEmpty || tree.source.uri != source.uri) return null;
    return identical(source, tree.source)
        ? this
        : _tryReparse(source, tree, languageVersion);
  }
}

ParseResult<CompilationUnit>? _tryReparse(
  SourceFile source,
  SyntaxTree previous,
  LanguageVersion languageVersion,
) {
  final before = previous.source.text, after = source.text;
  final limit = before.length < after.length ? before.length : after.length;
  final prefix = _matchingLength(before, 0, after, 0, limit);
  final edited = _editFunctionBody(source, previous, prefix, languageVersion);
  if (edited != null) return edited;
  final members = <int>[];
  int? scriptTag;
  final root = previous.root;
  for (var i = 0, n = previous.childCount(root); i < n; i++) {
    final child = previous.childAt(root, i);
    if (previous.end(child) > prefix) break;
    if (previous.kind(child) == .scriptTag) {
      scriptTag = child;
    } else {
      members.add(child);
    }
  }
  if (members.isEmpty) return null;
  final last = members.last, end = previous.end(last);
  if (end == 0) return null;
  final delimiter = after.codeUnitAt(end - 1);
  if (delimiter != 59 && delimiter != 125) return null;
  final suffix = scanFrom(source, end);
  if (suffix.hasErrors) return null;
  final arena = AstArena.prefix(previous, source, last, suffix.tokens.length);
  final parser = _Parser._(source, suffix.tokens, languageVersion, [], arena);
  final unit = _readUnit(parser, members, scriptTag);
  if (parser.diagnostics.isNotEmpty) return null;
  return parser.finishResult(unit);
}

// Compare four UTF-16 units per loop without copying either source range.
int _matchingLength(String a, int startA, String b, int startB, int length) {
  var i = 0;
  while (i + 4 <= length &&
      a.codeUnitAt(startA + i) == b.codeUnitAt(startB + i) &&
      a.codeUnitAt(startA + i + 1) == b.codeUnitAt(startB + i + 1) &&
      a.codeUnitAt(startA + i + 2) == b.codeUnitAt(startB + i + 2) &&
      a.codeUnitAt(startA + i + 3) == b.codeUnitAt(startB + i + 3)) {
    i += 4;
  }
  while (i < length && a.codeUnitAt(startA + i) == b.codeUnitAt(startB + i)) {
    i++;
  }
  return i;
}

ParseResult<CompilationUnit>? _editFunctionBody(
  SourceFile source,
  SyntaxTree tree,
  int change,
  LanguageVersion version,
) {
  var row = tree.root;
  while (tree.childCount(row) != 0) {
    var low = 0, high = tree.childCount(row);
    while (low < high) {
      final mid = (low + high) >>> 1;
      if (tree.end(tree.childAt(row, mid)) <= change) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == tree.childCount(row)) return null;
    final child = tree.childAt(row, low);
    final start = tree.start(child), end = tree.end(child);
    if (change < start) return null;
    if (tree.kind(row) == SyntaxKind.methodDeclaration ||
        tree.kind(row) == SyntaxKind.topLevelFunctionDeclaration) {
      if (low != tree.childCount(row) - 1 ||
          start >= change ||
          tree.kind(child) != SyntaxKind.blockStatement &&
              tree.kind(child) != SyntaxKind.expressionFunctionBody &&
              tree.kind(child) != SyntaxKind.modifiedBlockFunctionBody) {
        return null;
      }
      // A tail edit is already covered by the compilation-unit prefix.
      if (source.length - end < end - start) return null;
      final before = tree.source.text, after = source.text;
      final delta = after.length - before.length, newEnd = end + delta;
      if (newEnd <= change) return null;
      final suffix = before.length - end + 1;
      if (_matchingLength(before, end - 1, after, newEnd - 1, suffix) !=
          suffix) {
        return null;
      }
      final body = scanFrom(source, start, newEnd);
      if (body.hasErrors || body.tokens.last.start != newEnd) return null;
      var first = child;
      while (tree.childCount(first) != 0) {
        first = tree.childAt(first, 0);
      }
      final arena = AstArena.edit(tree, source, first);
      final parser = _Parser._(source, body.tokens, version, [], arena);
      final replacement = _BodyReader(parser).finish();
      if (parser.current.kind != .eof ||
          parser.diagnostics.isNotEmpty ||
          arena.rStart(replacement) != start ||
          arena.rEnd(replacement) != newEnd ||
          !arena.finishEdit(tree, child, replacement)) {
        return null;
      }
      return parser.finishResult(tree.root);
    }
    row = child;
  }
  return null;
}

int _readUnit(_Parser parser, [List<int>? prefix, int? scriptTag]) {
  if (parser.current.kind == .scriptTag) {
    final token = parser.current;
    scriptTag = parser.arena.putScriptTag(start: token.start, end: token.end);
    parser.advance();
  }
  final members = prefix ?? <int>[];
  final lastKind = members.isEmpty ? null : parser.arena.kindAt(members.last);
  var parts = lastKind == .partDirective || lastKind == .partOfDirective;
  var partOf = lastKind == .partOfDirective;
  var declarations =
      lastKind != null &&
      !parts &&
      lastKind != .importDirective &&
      lastKind != .exportDirective &&
      lastKind != .libraryDirective;
  while (parser.current.kind != .eof) {
    final initial = parser.cursor;
    final start = parser.current.start;
    List<int> metadata = const [];
    if (parser.current.kind == .at) {
      metadata = _MetadataReader(parser).finish();
    }
    final kind = parser.current.kind;
    if ((kind == .keywordLibrary ||
            kind == .keywordImport ||
            kind == .keywordExport ||
            kind == .keywordPart) &&
        !parser.hasParametersAfterName) {
      if (declarations ||
          partOf ||
          kind == .keywordLibrary && members.isNotEmpty ||
          parts && kind != .keywordPart) {
        parser.error(
          'misplaced_directive',
          'This directive is out of order.',
          parser.current,
        );
      }
      if (kind == .keywordPart) {
        parts = true;
        if (parser.tokens[parser.cursor + 1].kind == .keywordOf) {
          if (members.isNotEmpty) {
            parser.error(
              'misplaced_directive',
              'A part-of directive must precede declarations.',
              parser.current,
            );
          }
          partOf = true;
        }
      }
      members.add(_readDirective(parser, start, metadata));
    } else {
      declarations = true;
      members.add(_TopLevelReader(parser, start, metadata).read());
    }
    if (parser.cursor == initial && parser.current.kind != .eof) {
      parser.unexpected();
    }
  }
  return parser.arena.putCompilationUnit(
    scriptTag: scriptTag,
    members: members,
  );
}
