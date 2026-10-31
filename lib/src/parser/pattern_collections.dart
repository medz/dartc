part of 'parser.dart';

final class _CollectionPatternReader(
  final _Parser parser,
  final PatternContext context,
) extends _Reader<DartPattern> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final start = parser.current.start;
    TypeArgumentList? arguments;
    if (parser.current.kind == .less) {
      final reader = _TypeReader(parser);
      if (!reader.start(arguments: true)) yield _TypeTask(reader);
      arguments = reader.result as TypeArgumentList?;
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
    final opening = parser.current;
    if (opening.kind == .emptyBrackets ||
        opening.kind == .emptyBracketsAssign) {
      parser.consumeEmptyBrackets();
      result = ListPattern(
        source: parser.source,
        start: start,
        end: opening.start + 2,
        typeArguments: arguments,
        elements: const [],
      );
      return;
    }
    final isMap = opening.kind == .leftBrace;
    final closing = isMap ? TokenKind.rightBrace : TokenKind.rightBracket;
    parser.expect(isMap ? .leftBrace : .leftBracket);
    final elements = <AstNode>[];
    var hasRest = false;
    while (parser.current.kind != closing && parser.current.kind != .eof) {
      final cursor = parser.cursor;
      final token = parser.current;
      if (token.kind == .spread) {
        if (hasRest) {
          parser.error(
            'duplicate_rest_pattern',
            'A pattern can contain only one rest element.',
            token,
          );
        }
        hasRest = true;
        if (isMap) {
          parser.error(
            'rest_in_map_pattern',
            'A map pattern cannot contain a rest element.',
            token,
          );
        }
        parser.advance();
        DartPattern? pattern;
        if (parser.current.kind != .comma && parser.current.kind != closing) {
          final reader = _PatternReader(parser, context: context);
          yield reader;
          pattern = reader.result;
        }
        elements.add(
          RestPatternElement(
            source: parser.source,
            start: token.start,
            end: pattern?.end ?? token.end,
            pattern: pattern,
          ),
        );
      } else {
        Expression? key;
        if (isMap) {
          final reader = _ExpressionReader(parser);
          if (!reader.start()) yield reader;
          key = reader.result;
          parser.expect(.colon);
        }
        final reader = _PatternReader(parser, context: context);
        yield reader;
        final pattern = reader.result;
        elements.add(
          key == null
              ? pattern
              : MapPatternEntry(
                  source: parser.source,
                  start: key.start,
                  end: pattern.end,
                  key: key,
                  value: pattern,
                ),
        );
      }
      if (parser.current.kind != .comma) break;
      parser.advance();
      if (parser.cursor == cursor) break;
    }
    final end = parser.expect(closing);
    result = isMap
        ? MapPattern(
            source: parser.source,
            start: start,
            end: end,
            typeArguments: arguments,
            elements: elements.cast<MapPatternElement>(),
          )
        : ListPattern(
            source: parser.source,
            start: start,
            end: end,
            typeArguments: arguments,
            elements: elements.cast<ListPatternElement>(),
          );
  }
}

final class _PatternFieldsReader(
  final _Parser parser,
  final PatternContext context, {
  final bool object = false,
}) extends _Reader<List<PatternField>> {
  bool hasComma = false;
  late int end;

  @override
  Iterable<_Reader<Object?>> read() sync* {
    parser.expect(.leftParen);
    final fields = <PatternField>[];
    while (parser.current.kind != .rightParen && parser.current.kind != .eof) {
      final token = parser.current;
      Identifier? name;
      if (token.kind.isIdentifier &&
          parser.tokens[parser.cursor + 1].kind == .colon) {
        name = parser.identifier(token);
        parser.advance();
      }
      final isNamed = parser.current.kind == .colon;
      if (isNamed) parser.advance();
      final reader = _PatternReader(parser, context: context);
      yield reader;
      final pattern = reader.result;
      if (isNamed) {
        fields.add(
          NamedPatternField(
            source: parser.source,
            start: token.start,
            end: pattern.end,
            name: name,
            pattern: pattern,
          ),
        );
      } else {
        if (object) {
          parser.error(
            'expected_named_pattern_field',
            'Expected a named pattern field.',
            token,
          );
        }
        fields.add(pattern);
      }
      if (parser.current.kind != .comma) break;
      hasComma = true;
      parser.advance();
    }
    end = parser.expect(.rightParen);
    result = fields;
  }
}
