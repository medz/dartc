part of 'parser.dart';

/// Parses one statement through the end of [input].
///
/// Blocks, local variables, loops, branches, labels, jumps, assertions and
/// try/catch/finally retain their written order. Expressions use the same
/// synchronous context as [parseExpression]. Patterns, local functions and
/// switch statements are not yet parsed. Binding, types and jump targets are
/// not checked. Recovery may return only part of invalid input.
ParseResult<Statement> parseStatement(ScanResult input) {
  final parser = _Parser(input);
  final node = _StatementReader(parser).read();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return ParseResult._(node, parser.diagnostics);
}

sealed class _StatementFrame(final Token opening);

final class _Block(super.opening) extends _StatementFrame {
  final List<Statement> statements = [];
}

final class _IfStatement(super.opening, final Expression condition)
    extends _StatementFrame {
  Statement? thenStatement;
}

final class _WhileStatement(super.opening, final Expression condition)
    extends _StatementFrame;

final class _DoStatement(super.opening) extends _StatementFrame;

final class _ForStatement(
  super.opening,
  final ForLoopParts parts,
  final bool isAwait,
) extends _StatementFrame;

final class _Labels(super.opening, final List<Label> labels)
    extends _StatementFrame;

final class _CatchHeader(
  final Token opening,
  final TypeAnnotation? type,
  final Identifier? exception,
  final Identifier? stackTrace,
);

final class _TryStatement(super.opening) extends _StatementFrame {
  BlockStatement? body;
  final List<CatchClause> clauses = [];
  _CatchHeader? handler;
  bool isFinally = false;
}

final class _StatementReader(final _Parser parser) {
  final List<_StatementFrame> frames = [];

  SourceFile get source => parser.source;
  Token get current => parser.current;

  Statement read() {
    Statement? result;
    while (true) {
      result ??= start();
      if (result == null) continue;
      if (frames.isEmpty) return result;
      result = finish(result);
    }
  }

  Statement? start() {
    final frame = frames.lastOrNull;
    final token = current;
    if (frame is _Block &&
        (token.kind == .rightBrace ||
            token.kind == .eof ||
            token.kind == .keywordElse ||
            token.kind == .keywordCatch ||
            token.kind == .keywordFinally)) {
      final end = parser.expect(.rightBrace);
      frames.removeLast();
      return BlockStatement(
        source: source,
        start: frame.opening.start,
        end: end,
        statements: frame.statements,
      );
    }
    if (frame is _TryStatement && token.kind != .leftBrace) {
      parser.error('expected_block', 'Expected a block.', token);
      return BlockStatement(
        source: source,
        start: token.start,
        end: token.start,
        statements: const [],
      );
    }
    if (token.kind == .eof ||
        token.kind == .rightBrace ||
        token.kind == .keywordElse && frame is _IfStatement) {
      parser.error('expected_statement', 'Expected a statement.', token);
      return MissingStatement(source: source, offset: token.start);
    }
    if (token.kind.isIdentifier &&
        parser.tokens[parser.cursor + 1].kind == .colon) {
      final labels = <Label>[];
      do {
        final name = parser.identifier(current);
        parser.advance();
        final end = current.end;
        parser.advance();
        labels.add(
          Label(source: source, start: name.start, end: end, name: name),
        );
      } while (current.kind.isIdentifier &&
          parser.tokens[parser.cursor + 1].kind == .colon);
      frames.add(_Labels(token, labels));
      return null;
    }
    switch (token.kind) {
      case .leftBrace:
        parser.advance();
        frames.add(_Block(token));
        return null;
      case .semicolon:
        parser.advance();
        return EmptyStatement(
          source: source,
          start: token.start,
          end: token.end,
        );
      case .keywordIf:
        parser.advance();
        frames.add(_IfStatement(token, condition()));
        return null;
      case .keywordWhile:
        parser.advance();
        frames.add(_WhileStatement(token, condition()));
        return null;
      case .keywordDo:
        parser.advance();
        frames.add(_DoStatement(token));
        return null;
      case .keywordFor || .keywordAwait
          when token.kind == .keywordFor ||
              parser.tokens[parser.cursor + 1].kind == .keywordFor:
        final isAwait = token.kind == .keywordAwait;
        if (isAwait) {
          parser.error(
            'await_in_sync',
            'An await-for requires an asynchronous context.',
            token,
          );
          parser.advance();
        }
        parser.advance();
        final parts = parser.readForStatementHeader();
        frames.add(_ForStatement(token, parts, isAwait));
        return null;
      case .keywordTry:
        parser.advance();
        frames.add(_TryStatement(token));
        return null;
      case .keywordReturn:
        parser.advance();
        final expression =
            current.kind == .semicolon ||
                current.kind == .rightBrace ||
                current.kind == .eof
            ? null
            : parser.readEmbeddedExpression();
        final end = parser.expect(.semicolon);
        return ReturnStatement(
          source: source,
          start: token.start,
          end: end,
          expression: expression,
        );
      case .keywordBreak || .keywordContinue:
        parser.advance();
        Identifier? label;
        if (current.kind.isIdentifier) {
          label = parser.identifier(current);
          parser.advance();
        }
        final end = parser.expect(.semicolon);
        return token.kind == .keywordBreak
            ? BreakStatement(
                source: source,
                start: token.start,
                end: end,
                label: label,
              )
            : ContinueStatement(
                source: source,
                start: token.start,
                end: end,
                label: label,
              );
      case .keywordRethrow:
        parser.advance();
        return RethrowStatement(
          source: source,
          start: token.start,
          end: parser.expect(.semicolon),
        );
      case .keywordAssert:
        return assertion();
      case .keywordSwitch || .at:
        parser.error(
          'unsupported_syntax',
          'This statement syntax is not yet supported.',
          token,
        );
        parser.advance();
        return MissingStatement(source: source, offset: token.start);
      default:
        final declarations = parser.readVariableDeclarations();
        if (declarations != null) return variables(declarations);
        final start = parser.cursor;
        final expression = parser.readEmbeddedExpression();
        final end = parser.expect(.semicolon);
        if (parser.cursor == start && current.kind != .eof) parser.unexpected();
        return ExpressionStatement(
          source: source,
          start: expression.start,
          end: end,
          expression: expression,
        );
    }
  }

  Expression condition() {
    parser.expect(.leftParen);
    final expression = parser.readEmbeddedExpression();
    if (current.kind == .keywordCase) {
      parser.error(
        'unsupported_syntax',
        'Case pattern parsing is not yet supported.',
        current,
      );
      // Continue to the header boundary without treating pattern tokens as
      // a valid boolean condition.
      parser.advance();
      parser.readEmbeddedExpression();
    }
    parser.expect(.rightParen);
    return expression;
  }

  Statement assertion() {
    final keyword = current;
    parser.advance();
    parser.expect(.leftParen);
    final expression = parser.readEmbeddedExpression();
    Expression? message;
    if (current.kind == .comma) {
      parser.advance();
      if (current.kind != .rightParen) {
        message = parser.readEmbeddedExpression();
        if (current.kind == .comma) parser.advance();
      }
    }
    parser.expect(.rightParen);
    return AssertStatement(
      source: source,
      start: keyword.start,
      end: parser.expect(.semicolon),
      condition: expression,
      message: message,
    );
  }

  Statement variables(_VariableDeclarations declarations) {
    while (true) {
      Expression? initializer;
      if (current.kind == .assign) {
        parser.advance();
        initializer = parser.readEmbeddedExpression();
      }
      declarations.variables.add(
        VariableDeclaration(
          source: source,
          start: declarations.name.start,
          end: initializer?.end ?? declarations.name.end,
          name: declarations.name,
          initializer: initializer,
        ),
      );
      if (current.kind != .comma) break;
      parser.advance();
      declarations.name = parser.readVariableName();
    }
    final variables = VariableDeclarationList(
      source: source,
      start: declarations.start,
      end: declarations.variables.last.end,
      keyword: declarations.keyword,
      isLate: declarations.isLate,
      type: declarations.type,
      declarations: declarations.variables,
    );
    return VariableDeclarationStatement(
      source: source,
      start: variables.start,
      end: parser.expect(.semicolon),
      variables: variables,
    );
  }

  Statement? finish(Statement statement) {
    final frame = frames.last;
    switch (frame) {
      case _Block():
        frame.statements.add(statement);
        return null;
      case _IfStatement():
        if (frame.thenStatement == null) {
          frame.thenStatement = statement;
          if (current.kind == .keywordElse) {
            parser.advance();
            return null;
          }
          statement = IfStatement(
            source: source,
            start: frame.opening.start,
            end: statement.end,
            condition: frame.condition,
            thenStatement: statement,
          );
        } else {
          statement = IfStatement(
            source: source,
            start: frame.opening.start,
            end: statement.end,
            condition: frame.condition,
            thenStatement: frame.thenStatement!,
            elseStatement: statement,
          );
        }
      case _WhileStatement():
        statement = WhileStatement(
          source: source,
          start: frame.opening.start,
          end: statement.end,
          condition: frame.condition,
          body: statement,
        );
      case _DoStatement():
        parser.expect(.keywordWhile);
        final test = condition();
        statement = DoStatement(
          source: source,
          start: frame.opening.start,
          end: parser.expect(.semicolon),
          body: statement,
          condition: test,
        );
      case _ForStatement():
        statement = ForStatement(
          source: source,
          start: frame.opening.start,
          end: statement.end,
          isAwait: frame.isAwait,
          parts: frame.parts,
          body: statement,
        );
      case _Labels():
        statement = LabeledStatement(
          source: source,
          start: frame.opening.start,
          end: statement.end,
          labels: frame.labels,
          statement: statement,
        );
      case _TryStatement():
        final block = statement as BlockStatement;
        if (frame.isFinally) {
          statement = TryStatement(
            source: source,
            start: frame.opening.start,
            end: block.end,
            body: frame.body!,
            catchClauses: frame.clauses,
            finallyBlock: block,
          );
        } else {
          if (frame.handler case final handler?) {
            frame.clauses.add(
              CatchClause(
                source: source,
                start: handler.opening.start,
                end: block.end,
                exceptionType: handler.type,
                exceptionParameter: handler.exception,
                stackTraceParameter: handler.stackTrace,
                body: block,
              ),
            );
            frame.handler = null;
          } else {
            frame.body = block;
          }
          if (current.kind == .keywordOn || current.kind == .keywordCatch) {
            frame.handler = catchHeader();
            return null;
          }
          if (current.kind == .keywordFinally) {
            parser.advance();
            frame.isFinally = true;
            return null;
          }
          if (frame.clauses.isEmpty) {
            parser.error(
              'expected_handler',
              'Expected an on, catch, or finally clause.',
              current,
            );
          }
          statement = TryStatement(
            source: source,
            start: frame.opening.start,
            end: block.end,
            body: frame.body!,
            catchClauses: frame.clauses,
          );
        }
    }
    frames.removeLast();
    return statement;
  }

  _CatchHeader catchHeader() {
    final keyword = current;
    TypeAnnotation? type;
    Identifier? exception;
    Identifier? stackTrace;
    if (current.kind == .keywordOn) {
      parser.advance();
      final start = current.start;
      final reader = _TypeReader(parser);
      type =
          reader.read() as TypeAnnotation? ??
          MissingTypeAnnotation(source: source, offset: start);
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
    if (current.kind == .keywordCatch) {
      parser.advance();
      parser.expect(.leftParen);
      exception = parser.readVariableName();
      if (current.kind == .comma) {
        parser.advance();
        stackTrace = parser.readVariableName();
      }
      parser.expect(.rightParen);
    }
    return _CatchHeader(keyword, type, exception, stackTrace);
  }
}

extension on _Parser {
  int expect(TokenKind kind) {
    final token = current;
    if (token.kind == kind) {
      advance();
      return token.end;
    }
    error('expected_token', "Expected '${kind.spelling}'.", token);
    return token.start;
  }

  Expression readEmbeddedExpression() {
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    expectsOperand = true;
    hasSyntaxError = false;
    selectorTarget = null;
    postfixTarget = null;
    checkedNullAware = false;
    if (run(trial: false, boundary: .expression)) {
      parseWithTrials(boundary: .expression);
    }
    final result = finishExpression(0, 0);
    assert(prefixes.isEmpty && questions.isEmpty);
    return result;
  }

  ForLoopParts readForStatementHeader() {
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    final opening = current;
    expect(.leftParen);
    final header = _ForStatementHeader(opening, 0, 0, current.start);
    frames.add(header);
    expectsOperand = true;
    hasSyntaxError = false;
    initializeForHeader(header);
    if (nullableForInitializer != null ||
        run(trial: false, boundary: .header)) {
      parseWithTrials(boundary: .header);
    }
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    return header.parts;
  }
}
