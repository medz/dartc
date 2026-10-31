part of 'parser.dart';

/// Parses a source file into ordered directives and declarations.
///
/// The unit spans the whole source, including comments and whitespace. Imports
/// remain written URIs; parsing does not load dependencies or bind names.
/// Unsupported or incomplete members produce diagnostics. Check [ParseResult.hasErrors]
/// before treating a unit as valid syntax.
ParseResult<CompilationUnit> parseCompilationUnit(ScanResult input) {
  final parser = _Parser(input);
  final node = _UnitReader(parser).finish();
  return ParseResult._(node, parser.diagnostics);
}

final class _UnitReader(final _Parser parser) extends _Reader<CompilationUnit> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    ScriptTag? scriptTag;
    if (parser.current.kind == .scriptTag) {
      final token = parser.current;
      scriptTag = ScriptTag(
        source: parser.source,
        start: token.start,
        end: token.end,
      );
      parser.advance();
    }
    final members = <CompilationUnitMember>[];
    var declarations = false;
    var parts = false;
    var partOf = false;
    while (parser.current.kind != .eof) {
      final initial = parser.cursor;
      final start = parser.current.start;
      final annotations = _MetadataReader(parser);
      yield annotations;
      final metadata = annotations.result;
      final kind = parser.current.kind;
      if (kind == .keywordLibrary ||
          kind == .keywordImport ||
          kind == .keywordExport ||
          kind == .keywordPart) {
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
        final reader = _DirectiveReader(parser, start, metadata);
        yield reader;
        members.add(reader.result);
      } else {
        declarations = true;
        final reader = _TopLevelReader(parser, start, metadata);
        yield reader;
        members.add(reader.result);
      }
      if (parser.cursor == initial && parser.current.kind != .eof) {
        parser.unexpected();
      }
    }
    result = CompilationUnit(
      source: parser.source,
      scriptTag: scriptTag,
      members: members,
    );
  }
}
