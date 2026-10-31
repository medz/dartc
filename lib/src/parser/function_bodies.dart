part of 'parser.dart';

/// Parses a declaration's function body through the end of [input].
///
/// Accepts blocks, `async` blocks and arrow bodies, `sync*` and `async*` blocks,
/// and empty bodies. Arrow and empty bodies include their semicolon. The written
/// modifier determines the context for `await`, `yield` and `await for`.
///
/// The enclosing declaration is unknown: whether it permits an empty body is
/// not checked. Name binding, return types and yielded types need analysis.
/// Invalid syntax produces diagnostics. A missing body produces a zero-width
/// [MissingFunctionBody].
ParseResult<FunctionBody> parseFunctionBody(ScanResult input) {
  final parser = _Parser(input);
  final body = _BodyReader(parser).finish();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return ParseResult._(body, parser.diagnostics);
}

final class _BodyReader(final _Parser parser, {final bool declaration = true})
    extends _Reader<FunctionBody> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final start = parser.current.start;
    final previous = parser.functionModifier;
    parser.functionModifier = null;
    if (parser.current.kind == .keywordAsync ||
        parser.current.kind == .keywordSync) {
      final token = parser.current;
      parser.advance();
      if (parser.current.kind == .star) {
        parser.functionModifier = token.kind == .keywordAsync
            ? .asyncStar
            : .syncStar;
        parser.advance();
      } else if (token.kind == .keywordAsync) {
        parser.functionModifier = .asyncKeyword;
      } else {
        parser.error(
          'invalid_sync_modifier',
          "The sync modifier requires '*'.",
          token,
        );
      }
    }
    try {
      switch (parser.current.kind) {
        case .semicolon:
          final token = parser.current;
          if (!declaration) {
            parser.error(
              'expected_function_body',
              'A function expression requires a body.',
              token,
            );
          }
          if (parser.functionModifier != null) {
            parser.error(
              'modified_empty_body',
              'An empty body cannot have a function modifier.',
              token,
            );
          }
          parser.advance();
          result = EmptyFunctionBody(
            source: parser.source,
            start: start,
            end: token.end,
          );
          return;
        case .arrow:
          if (parser.inGenerator) {
            parser.error(
              'generator_arrow_body',
              'A generator requires a block body.',
              parser.current,
            );
          }
          parser.advance();
          final reader = _ExpressionReader(parser);
          if (!reader.start()) yield reader;
          final expression = reader.result;
          result = ExpressionFunctionBody(
            source: parser.source,
            start: start,
            end: declaration ? parser.expect(.semicolon) : expression.end,
            isAsync: parser.inAsync,
            expression: expression,
          );
          return;
        case .leftBrace:
          final reader = _StatementReader(parser, requireBlock: true);
          yield reader;
          final block = reader.result as BlockStatement;
          final modifier = parser.functionModifier;
          result = modifier == null
              ? block
              : ModifiedBlockFunctionBody(
                  source: parser.source,
                  start: start,
                  end: block.end,
                  modifier: modifier,
                  block: block,
                );
          return;
        default:
          parser.error(
            'expected_function_body',
            'Expected a function body.',
            parser.current,
          );
          result = MissingFunctionBody(
            source: parser.source,
            offset: parser.current.start,
          );
      }
    } finally {
      parser.functionModifier = previous;
    }
  }
}
