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

int _readUnit(_Parser parser) {
  int? scriptTag;
  if (parser.current.kind == .scriptTag) {
    final token = parser.current;
    scriptTag = parser.arena.putScriptTag(start: token.start, end: token.end);
    parser.advance();
  }
  final members = <int>[];
  var declarations = false;
  var parts = false;
  var partOf = false;
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
