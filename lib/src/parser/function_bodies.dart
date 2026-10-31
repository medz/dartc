part of 'parser.dart';

/// Parses a declaration's function body through the end of [input].
///
/// Accepts blocks, `async` blocks and arrow bodies, `sync*` and `async*` blocks,
/// and empty bodies. Arrow and empty bodies include their semicolon. The written
/// modifier determines the context for `await`, `yield` and `await for`.
///
/// The enclosing declaration is unknown: whether it permits an empty body is
/// not checked. Name binding, return types and yielded types need analysis.
/// Unsupported statement and expression forms produce diagnostics. A missing
/// body produces a zero-width [MissingFunctionBody].
ParseResult<FunctionBody> parseFunctionBody(ScanResult input) {
  final parser = _Parser(input);
  final body = parser.readFunctionBody();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return ParseResult._(body, parser.diagnostics);
}

extension on _Parser {
  FunctionBody readFunctionBody() {
    final start = current.start;
    final previous = functionModifier;
    functionModifier = null;
    if (current.kind == .keywordAsync || current.kind == .keywordSync) {
      final token = current;
      advance();
      if (current.kind == .star) {
        functionModifier = token.kind == .keywordAsync ? .asyncStar : .syncStar;
        advance();
      } else if (token.kind == .keywordAsync) {
        functionModifier = .asyncKeyword;
      } else {
        error(
          'invalid_sync_modifier',
          "The sync modifier requires '*'.",
          token,
        );
      }
    }
    try {
      switch (current.kind) {
        case .semicolon:
          final token = current;
          if (functionModifier != null) {
            error(
              'modified_empty_body',
              'An empty body cannot have a function modifier.',
              token,
            );
          }
          advance();
          return EmptyFunctionBody(
            source: source,
            start: start,
            end: token.end,
          );
        case .arrow:
          if (inGenerator) {
            error(
              'generator_arrow_body',
              'A generator requires a block body.',
              current,
            );
          }
          advance();
          final expression = readEmbeddedExpression();
          return ExpressionFunctionBody(
            source: source,
            start: start,
            end: expect(.semicolon),
            isAsync: inAsync,
            expression: expression,
          );
        case .leftBrace:
          final block = _StatementReader(this).read() as BlockStatement;
          final modifier = functionModifier;
          return modifier == null
              ? block
              : ModifiedBlockFunctionBody(
                  source: source,
                  start: start,
                  end: block.end,
                  modifier: modifier,
                  block: block,
                );
        default:
          error('expected_function_body', 'Expected a function body.', current);
          return MissingFunctionBody(source: source, offset: current.start);
      }
    } finally {
      functionModifier = previous;
    }
  }
}
