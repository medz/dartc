part of 'parser.dart';

/// Parses one statement through the end of [input].
///
/// Blocks, local variables, loops, branches, labels, jumps, assertions and
/// try/catch/finally retain their written order. Expressions use the same
/// synchronous context as [parseExpression]. Local functions retain their own
/// body context. Case patterns, guards, switches and destructuring preserve
/// their written structure. Unlabeled jumps require an enclosing loop or switch;
/// nested function bodies start a new jump context. Label binding, types and
/// resolved jump targets require analysis.
/// Recovery may return only part of invalid input.
ParseResult<Statement> parseStatement(
  ScanResult input, {
  LanguageVersion languageVersion = LanguageVersion.current,
}) {
  final parser = _Parser(input, languageVersion: languageVersion);
  final node = _StatementReader(parser).finish();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return parser.finishResult(node);
}

sealed class _StatementFrame(final Token opening);

final class _Block(super.opening) extends _StatementFrame {
  final List<int> statements = [];
}

final class _IfStatement(
  super.opening,
  final int condition,
  final int? casePattern,
) extends _StatementFrame {
  int? thenStatement;
}

final class _WhileStatement(super.opening, final int condition)
    extends _StatementFrame;

final class _DoStatement(super.opening) extends _StatementFrame;

final class _ForStatement(super.opening, final int parts, final bool isAwait)
    extends _StatementFrame;

final class _Labels(super.opening, final List<int> labels)
    extends _StatementFrame;

final class _CatchHeader(
  final Token opening,
  final int? type,
  final int? exception,
  final int? stackTrace,
);

final class _TryStatement(super.opening) extends _StatementFrame {
  int? body;
  final List<int> clauses = [];
  _CatchHeader? handler;
  bool isFinally = false;
}

final class _StatementReader(
  final _Parser parser, {
  final bool requireBlock = false,
}) extends _Reader<int> {
  final List<_StatementFrame> frames = [];
  int? value;

  SourceFile get source => parser.source;
  Token get current => parser.current;

  @override
  Iterable<_Reader<Object?>> read() sync* {
    while (true) {
      if (value == null) {
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
          value = parser.arena.blockStatement(
            start: frame.opening.start,
            end: end,
            statements: frame.statements,
          );
          continue;
        }
        if (frame is _TryStatement && token.kind != .leftBrace) {
          parser.error('expected_block', 'Expected a block.', token);
          value = parser.arena.blockStatement(
            start: token.start,
            end: token.start,
            statements: const [],
          );
          continue;
        }
        if (token.kind == .eof ||
            token.kind == .rightBrace ||
            token.kind == .keywordElse && frame is _IfStatement) {
          parser.error('expected_statement', 'Expected a statement.', token);
          value = parser.arena.missingStatement(offset: token.start);
          continue;
        }
        if (token.kind.isIdentifier &&
            token.kind != .keywordAwait &&
            parser.tokens[parser.cursor + 1].kind == .colon) {
          final labels = <int>[];
          do {
            final name = parser.identifier(current);
            parser.advance();
            final end = current.end;
            parser.advance();
            labels.add(parser.arena.label(end: end, name: name));
          } while (current.kind.isIdentifier &&
              parser.tokens[parser.cursor + 1].kind == .colon);
          frames.add(_Labels(token, labels));
          value = null;
          continue;
        }
        switch (token.kind) {
          case .leftBrace
              when frame is _TryStatement ||
                  requireBlock && frames.isEmpty ||
                  !parser.startsPatternAssignment:
            parser.advance();
            frames.add(_Block(token));
            value = null;
            continue;
          case .semicolon:
            parser.advance();
            value = parser.arena.emptyStatement(
              start: token.start,
              end: token.end,
            );
            continue;
          case .keywordIf:
            parser.advance();
            final reader = _ConditionReader(parser, allowCase: true);
            yield reader;
            frames.add(_IfStatement(token, reader.result, reader.casePattern));
            value = null;
            continue;
          case .keywordWhile:
            parser.advance();
            final reader = _ConditionReader(parser);
            yield reader;
            frames.add(_WhileStatement(token, reader.result));
            parser.loopDepth++;
            value = null;
            continue;
          case .keywordDo:
            parser.advance();
            frames.add(_DoStatement(token));
            parser.loopDepth++;
            value = null;
            continue;
          case .keywordFor || .keywordAwait
              when token.kind == .keywordFor ||
                  parser.tokens[parser.cursor + 1].kind == .keywordFor:
            final isAwait = token.kind == .keywordAwait;
            if (isAwait) {
              if (!parser.inAsync) {
                parser.error(
                  'await_in_sync',
                  'An await-for requires an asynchronous context.',
                  token,
                );
              }
              parser.advance();
            }
            parser.advance();
            final reader = _ForHeaderReader(parser);
            yield reader;
            final parts = reader.result;
            if (isAwait && !parser.arena.isKind(parts, .forInParts)) {
              parser.error(
                'invalid_await_for',
                'An await-for requires a for-in header.',
                token,
              );
            }
            frames.add(_ForStatement(token, parts, isAwait));
            parser.loopDepth++;
            value = null;
            continue;
          case .keywordTry:
            parser.advance();
            frames.add(_TryStatement(token));
            value = null;
            continue;
          case .keywordReturn:
            parser.advance();
            int? expression;
            if (current.kind != .semicolon &&
                current.kind != .rightBrace &&
                current.kind != .eof) {
              final reader = _ExpressionReader(parser);
              if (!reader.start()) yield reader;
              expression = reader.result;
            }
            final end = parser.expect(.semicolon);
            if (expression != null && parser.inGenerator) {
              parser.error(
                'generator_return_value',
                'A generator cannot return a value.',
                token,
              );
            }
            value = parser.arena.returnStatement(
              start: token.start,
              end: end,
              expression: expression,
            );
            continue;
          case .keywordBreak || .keywordContinue:
            parser.advance();
            int? label;
            if (current.kind.isIdentifier) {
              label = parser.identifier(current);
              parser.advance();
            }
            final end = parser.expect(.semicolon);
            if (token.kind == .keywordBreak &&
                label == null &&
                parser.loopDepth == 0 &&
                parser.switchDepth == 0) {
              parser.error(
                'break_outside_loop_or_switch',
                'An unlabeled break requires an enclosing loop or switch.',
                token,
              );
            }
            if (token.kind == .keywordContinue && parser.loopDepth == 0) {
              if (parser.switchDepth == 0 || label == null) {
                parser.error(
                  'invalid_continue_context',
                  parser.switchDepth == 0
                      ? 'A continue requires an enclosing loop or switch.'
                      : 'A continue in a switch requires a label.',
                  token,
                );
              }
            }
            value = token.kind == .keywordBreak
                ? parser.arena.breakStatement(
                    start: token.start,
                    end: end,
                    label: label,
                  )
                : parser.arena.continueStatement(
                    start: token.start,
                    end: end,
                    label: label,
                  );
            continue;
          case .keywordRethrow:
            parser.advance();
            value = parser.arena.rethrowStatement(
              start: token.start,
              end: parser.expect(.semicolon),
            );
            continue;
          case .keywordAssert:
            yield* assertion();
            continue;
          case .keywordYield when parser.functionModifier != null:
            parser.advance();
            final isStar = current.kind == .star;
            if (isStar) parser.advance();
            final reader = _ExpressionReader(parser);
            if (!reader.start()) yield reader;
            final expression = reader.result;
            if (!parser.inGenerator) {
              parser.error(
                'yield_outside_generator',
                'A yield statement requires a generator.',
                token,
              );
            }
            value = parser.arena.yieldStatement(
              start: token.start,
              end: parser.expect(.semicolon),
              isStar: isStar,
              expression: expression,
            );
            continue;
          case .keywordSwitch:
            final reader = _SwitchStatementReader(parser);
            yield reader;
            value = reader.result;
            continue;
          case .at:
            final function = parser.localFunction();
            if (function != null) {
              yield function;
              if (function.result != null) {
                value = function.result;
                continue;
              }
            }
            final metadata = _MetadataReader(parser);
            yield metadata;
            if (parser.isPatternDeclaration) {
              final reader = _PatternDeclarationReader(
                parser,
                metadata: metadata.result,
              );
              yield reader;
              value = parser.arena.patternVariableDeclarationStatement(
                start: token.start,
                end: parser.expect(.semicolon),
                declaration: reader.result,
              );
            } else {
              final reader = _VariableReader(parser);
              yield reader;
              if (reader.result case final declarations?) {
                yield* variables(declarations, metadata: metadata.result);
              } else {
                parser.error(
                  'expected_declaration',
                  'Expected a declaration after metadata.',
                  current,
                );
                value = parser.arena.missingStatement(offset: current.start);
              }
            }
            continue;
          default:
            if (parser.isPatternDeclaration) {
              final reader = _PatternDeclarationReader(parser);
              yield reader;
              value = parser.arena.patternVariableDeclarationStatement(
                start: token.start,
                end: parser.expect(.semicolon),
                declaration: reader.result,
              );
              continue;
            }
            _VariableDeclarations? declarations;
            if ((token.kind != .keywordAwait ||
                    parser.functionModifier == null) &&
                parser.canStartVariableDeclaration) {
              final reader = _VariableReader(parser);
              yield reader;
              declarations = reader.result;
            }
            if (declarations != null) {
              yield* variables(declarations);
              continue;
            }
            if (token.kind != .keywordAwait ||
                parser.functionModifier == null) {
              final function = parser.localFunction();
              if (function != null) {
                yield function;
                if (function.result != null) {
                  value = function.result;
                  continue;
                }
              }
            }
            final start = parser.cursor;
            final reader = _ExpressionReader(parser);
            if (!reader.start()) yield reader;
            final expression = reader.result;
            final end = parser.expect(.semicolon);
            if (parser.cursor == start && current.kind != .eof) {
              parser.unexpected();
            }
            value = parser.arena.expressionStatement(
              end: end,
              expression: expression,
            );
            continue;
        }
      } else {
        if (frames.isEmpty) {
          result = value!;
          return;
        }
        var statement = value!;

        final frame = frames.last;
        switch (frame) {
          case _Block():
            frame.statements.add(statement);
            value = null;
            continue;
          case _IfStatement():
            if (frame.thenStatement == null) {
              frame.thenStatement = statement;
              if (current.kind == .keywordElse) {
                parser.advance();
                value = null;
                continue;
              }
              statement = parser.arena.ifStatement(
                start: frame.opening.start,
                end: parser.arena.end(statement),
                condition: frame.condition,
                casePattern: frame.casePattern,
                thenStatement: statement,
              );
            } else {
              statement = parser.arena.ifStatement(
                start: frame.opening.start,
                end: parser.arena.end(statement),
                condition: frame.condition,
                casePattern: frame.casePattern,
                thenStatement: frame.thenStatement!,
                elseStatement: statement,
              );
            }
          case _WhileStatement():
            parser.loopDepth--;
            statement = parser.arena.whileStatement(
              start: frame.opening.start,

              condition: frame.condition,
              body: statement,
            );
          case _DoStatement():
            parser.loopDepth--;
            parser.expect(.keywordWhile);
            final reader = _ConditionReader(parser);
            yield reader;
            final test = reader.result;
            statement = parser.arena.doStatement(
              start: frame.opening.start,
              end: parser.expect(.semicolon),
              body: statement,
              condition: test,
            );
          case _ForStatement():
            parser.loopDepth--;
            statement = parser.arena.forStatement(
              start: frame.opening.start,

              isAwait: frame.isAwait,
              parts: frame.parts,
              body: statement,
            );
          case _Labels():
            statement = parser.arena.labeledStatement(
              start: frame.opening.start,

              labels: frame.labels,
              statement: statement,
            );
          case _TryStatement():
            final block = statement;
            if (frame.isFinally) {
              statement = parser.arena.tryStatement(
                start: frame.opening.start,
                end: parser.arena.end(block),
                body: frame.body!,
                catchClauses: frame.clauses,
                finallyBlock: block,
              );
            } else {
              if (frame.handler case final handler?) {
                frame.clauses.add(
                  parser.arena.catchClause(
                    start: handler.opening.start,

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
                yield* catchHeader(frame);
                value = null;
                continue;
              }
              if (current.kind == .keywordFinally) {
                parser.advance();
                frame.isFinally = true;
                value = null;
                continue;
              }
              if (frame.clauses.isEmpty) {
                parser.error(
                  'expected_handler',
                  'Expected an on, catch, or finally clause.',
                  current,
                );
              }
              statement = parser.arena.tryStatement(
                start: frame.opening.start,
                end: parser.arena.end(block),
                body: frame.body!,
                catchClauses: frame.clauses,
              );
            }
        }
        frames.removeLast();
        value = statement;
      }
    }
  }

  Iterable<_Reader<Object?>> assertion() sync* {
    final keyword = current;
    parser.advance();
    parser.expect(.leftParen);
    final reader = _ExpressionReader(parser);
    if (!reader.start()) yield reader;
    final expression = reader.result;
    int? message;
    if (current.kind == .comma) {
      parser.advance();
      if (current.kind != .rightParen) {
        final reader = _ExpressionReader(parser);
        if (!reader.start()) yield reader;
        message = reader.result;
        if (current.kind == .comma) parser.advance();
      }
    }
    parser.expect(.rightParen);
    value = parser.arena.assertStatement(
      start: keyword.start,
      end: parser.expect(.semicolon),
      condition: expression,
      message: message,
    );
    return;
  }

  Iterable<_Reader<Object?>> variables(
    _VariableDeclarations declarations, {
    List<int> metadata = const [],
  }) sync* {
    final reader = _VariablesReader(parser, declarations, metadata: metadata);
    yield reader;
    final variables = reader.result;
    value = parser.arena.variableDeclarationStatement(
      end: parser.expect(.semicolon),
      variables: variables,
    );
  }

  Iterable<_Reader<Object?>> catchHeader(_TryStatement frame) sync* {
    final keyword = current;
    int? type;
    int? exception;
    int? stackTrace;
    if (current.kind == .keywordOn) {
      parser.advance();
      final start = current.start;
      final reader = _TypeReader(parser);
      if (!reader.start()) yield _TypeTask(reader);
      type = reader.result ?? parser.arena.missingTypeAnnotation(offset: start);
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
    frame.handler = _CatchHeader(keyword, type, exception, stackTrace);
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
}
