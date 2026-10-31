import 'dart:collection';

import '../ast/nodes.dart';
import '../diagnostics/diagnostic.dart';
import '../scanner/scanner.dart';
import '../scanner/token.dart';
import '../scanner/token_kind.dart';
import '../source/source_file.dart';
import '../source/source_span.dart';

part 'delimiters.dart';
part 'operators.dart';
part 'type_annotations.dart';
part 'type_expressions.dart';
part 'function_types.dart';
part 'record_types.dart';

/// The syntax and diagnostics produced by parsing a source snapshot.
///
/// A node is returned even when recovery was necessary. Check [hasErrors]
/// before using the result as valid syntax.
final class ParseResult<T extends AstNode> {
  ParseResult._(this.node, List<Diagnostic> diagnostics)
    : diagnostics = diagnostics.isEmpty
          ? const []
          : UnmodifiableListView(diagnostics);

  /// The parsed node, possibly containing recovery placeholders.
  final T node;

  /// Lexical diagnostics followed by syntax diagnostics in discovery order.
  final List<Diagnostic> diagnostics;

  /// Whether a lexical or syntax error was reported.
  bool get hasErrors => diagnostics.any((d) => d.severity == .error);
}

/// Parses one expression through the end of [input], without a semicolon.
///
/// The context is synchronous: `await` and `yield` can be identifiers. Supported
/// forms include scalar and plain string literals, records, operators, generic
/// calls, type tests and casts, member access, and indexing. Other forms produce
/// diagnostics until their grammar is implemented. Parsing does not resolve
/// names or check types.
///
/// Recovery preserves the input tokens and uses zero-width [MissingExpression]
/// nodes for omitted operands. With errors, the returned node may cover only
/// part of the input.
ParseResult<Expression> parseExpression(ScanResult input) =>
    _Parser(input).parse();

final class _Parser {
  _Parser(ScanResult input)
    : source = input.source,
      tokens = input.tokens,
      current = input.tokens.first,
      diagnostics = [...input.diagnostics];

  final SourceFile source;
  final List<Token> tokens;
  final List<Diagnostic> diagnostics;
  final List<Expression> values = [];
  final List<Token> operators = [];
  // Operator indices used as prefixes, including the ambiguous '-' token.
  final List<int> prefixes = [];
  // Operator indices awaiting ':', limited by the current delimiter's base.
  final List<int> questions = [];
  final List<_Delimiter> delimiters = [];
  int cursor = 0;
  // Either tokens[cursor] or its unconsumed suffix after a closing type angle.
  Token current;
  // Completed and failed angle-bracket trials, confined to this source parse.
  Map<int, (TypeArgumentList, int, Token)?>? typeArguments;
  bool expectsOperand = true;

  int get operatorBase => delimiters.isEmpty ? 0 : delimiters.last.operatorBase;

  void advance() {
    current = tokens[++cursor];
  }

  ParseResult<Expression> parse() {
    while (current.kind != .eof || delimiters.isNotEmpty) {
      final token = current;
      if (token.kind == .eof ||
          token.kind == .rightParen ||
          token.kind == .rightBracket) {
        if (delimiters.isNotEmpty) {
          closeDelimiter();
        } else {
          unexpected();
        }
        continue;
      }
      if (token.kind == .comma) {
        if (delimiters.isNotEmpty && delimiters.last is _Sequence) {
          final frame = delimiters.last as _Sequence;
          finishElement(frame);
          if (frame is _Group) frame.hasComma = true;
          advance();
        } else {
          unexpected();
        }
        continue;
      }
      if (token.kind == .colon) {
        parseColon();
        continue;
      }
      if (expectsOperand) {
        final frame = delimiters.isEmpty ? null : delimiters.last;
        if (frame case _Sequence()
            when frame.name == null &&
                values.length == frame.valueBase &&
                operators.length == frame.operatorBase &&
                token.kind.isIdentifier &&
                tokens[cursor + 1].kind == .colon) {
          frame.name = identifier(token);
          advance();
          advance();
        } else {
          parseOperand();
        }
      } else {
        parseContinuation();
      }
    }
    final node = finishExpression(0, 0);
    assert(prefixes.isEmpty && questions.isEmpty);
    return ParseResult._(node, diagnostics);
  }

  void parseOperand() {
    final token = current;
    if (token.kind.isIdentifier) {
      values.add(
        IdentifierExpression(
          source: source,
          start: token.start,
          end: token.end,
          identifier: identifier(token),
        ),
      );
    } else {
      switch (token.kind) {
        case .leftParen:
          delimiters.add(_Group(token, values.length, operators.length));
          advance();
          return;
        case .minus || .bang || .tilde || .increment || .decrement:
          prefixes.add(operators.length);
          operators.add(token);
          advance();
          return;
        case .integer ||
            .hexadecimalInteger ||
            .doubleLiteral ||
            .keywordTrue ||
            .keywordFalse ||
            .keywordNull:
          values.add(
            LiteralExpression(
              source: source,
              start: token.start,
              end: token.end,
              kind: switch (token.kind) {
                .integer || .hexadecimalInteger => .integer,
                .doubleLiteral => .doubleLiteral,
                .keywordNull => .nullLiteral,
                _ => .boolean,
              },
            ),
          );
        case .keywordThis:
          values.add(
            ThisExpression(source: source, start: token.start, end: token.end),
          );
        case .stringLiteral:
          parseStrings();
          expectsOperand = false;
          return;
        case .invalid:
          advance();
          return;
        default:
          unexpected(unsupported: isUnsupported(token.kind));
          return;
      }
    }
    advance();
    expectsOperand = false;
  }

  void parseStrings() {
    StringLiteralExpression literal(Token t) =>
        StringLiteralExpression(source: source, start: t.start, end: t.end);
    final first = literal(current);
    advance();
    if (current.kind != .stringLiteral) {
      values.add(first);
      return;
    }
    final strings = <StringExpression>[first];
    do {
      strings.add(literal(current));
      advance();
    } while (current.kind == .stringLiteral);
    values.add(
      AdjacentStringsExpression(
        source: source,
        start: first.start,
        end: strings.last.end,
        strings: strings,
      ),
    );
  }

  void parseContinuation() {
    final token = current;
    switch (token.kind) {
      case .less:
        if (tryTypeArguments()) return;
      case .keywordAs || .keywordIs:
        parseTypeOperator();
        return;
      case .dot || .nullAwareAccess:
        checkSelector();
        advance();
        final name = current;
        final valid = name.kind.isIdentifier || name.kind == .keywordNew;
        if (!valid) {
          error('expected_identifier', 'Expected a member name.', name);
        } else {
          advance();
        }
        final target = values.removeLast();
        values.add(
          PropertyAccessExpression(
            source: source,
            start: target.start,
            end: valid ? name.end : name.start,
            target: target,
            property: valid
                ? identifier(name)
                : Identifier(
                    source: source,
                    start: name.start,
                    end: name.start,
                  ),
            isNullAware: token.kind == .nullAwareAccess,
          ),
        );
        return;
      case .leftParen:
        checkSelector();
        final callee = values.removeLast();
        delimiters.add(_Call(token, values.length, operators.length, callee));
        advance();
        expectsOperand = true;
        return;
      case .leftBracket || .emptyBrackets:
        openIndex(isNullAware: false);
        return;
      case .question:
        if (tokens[cursor + 1].kind == .leftBracket ||
            tokens[cursor + 1].kind == .emptyBrackets) {
          // A nested conditional can take priority over an index here. Its
          // then-branch starts with a list literal, whose grammar is pending.
          if (questions.isNotEmpty && questions.last >= operatorBase) {
            error(
              'unsupported_syntax',
              'List and null-aware index disambiguation in conditional '
                  'branches is not yet supported.',
              token,
            );
          }
          advance();
          openIndex(isNullAware: true);
          return;
        }
      case .bang:
        final operand = values.removeLast();
        values.add(
          NullAssertionExpression(
            source: source,
            start: operand.start,
            end: token.end,
            operand: operand,
          ),
        );
        advance();
        return;
      case .increment || .decrement:
        final operand = values.removeLast();
        checkAssignable(operand, token);
        values.add(
          UpdateExpression(
            source: source,
            start: operand.start,
            end: token.end,
            operand: operand,
            op: token.kind == .increment ? .increment : .decrement,
            isPrefix: false,
          ),
        );
        advance();
        return;
      default:
        break;
    }
    final precedence = token.kind.precedence;
    if (precedence == 0) {
      unexpected(unsupported: isUnsupported(token.kind));
      return;
    }
    while (operators.length > operatorBase) {
      final previous = operators.last;
      final previousPrecedence =
          prefixes.isNotEmpty && prefixes.last == operators.length - 1
          ? _prefixPrecedence
          : previous.kind.precedence;
      if (previous.kind == .question ||
          previousPrecedence < precedence ||
          previousPrecedence == precedence &&
              precedence == _assignmentPrecedence) {
        break;
      }
      if (previousPrecedence == precedence &&
          (precedence == _equalityPrecedence ||
              precedence == _relationalPrecedence)) {
        error(
          'chained_comparison',
          'Parenthesize this comparison operand.',
          token,
        );
      }
      reduce();
    }
    if (token.kind == .question) questions.add(operators.length);
    operators.add(token);
    advance();
    expectsOperand = true;
  }

  void parseColon() {
    if (questions.isEmpty || questions.last < operatorBase) {
      unexpected();
      return;
    }
    final question = questions.removeLast();
    ensureOperand();
    while (operators.length - 1 > question) {
      reduce();
    }
    advance();
    expectsOperand = true;
  }

  void reduce() {
    final operatorIndex = operators.length - 1;
    final token = operators.removeLast();
    final right = values.removeLast();
    if (prefixes.isNotEmpty && prefixes.last == operatorIndex) {
      prefixes.removeLast();
      if (token.kind == .increment || token.kind == .decrement) {
        checkAssignable(right, token);
        values.add(
          UpdateExpression(
            source: source,
            start: token.start,
            end: right.end,
            operand: right,
            op: token.kind == .increment ? .increment : .decrement,
            isPrefix: true,
          ),
        );
      } else {
        values.add(
          UnaryExpression(
            source: source,
            start: token.start,
            end: right.end,
            operand: right,
            op: switch (token.kind) {
              .minus => .negate,
              .bang => .logicalNot,
              _ => .bitwiseNot,
            },
          ),
        );
      }
      return;
    }
    if (token.kind == .question) {
      final Expression thenExpression;
      final Expression elseExpression;
      if (questions.isEmpty || questions.last != operatorIndex) {
        thenExpression = values.removeLast();
        elseExpression = right;
      } else {
        assert(questions.last == operators.length);
        questions.removeLast();
        error(
          'expected_colon',
          "Expected ':' in the conditional expression.",
          current,
        );
        thenExpression = right;
        elseExpression = MissingExpression(
          source: source,
          offset: current.start,
        );
      }
      final condition = values.removeLast();
      values.add(
        ConditionalExpression(
          source: source,
          start: condition.start,
          end: elseExpression.end,
          condition: condition,
          thenExpression: thenExpression,
          elseExpression: elseExpression,
        ),
      );
      return;
    }
    final left = values.removeLast();
    if (token.kind.precedence == _assignmentPrecedence) {
      if (token.kind == .assign &&
          (left is ParenthesizedExpression || left is RecordExpression)) {
        error(
          'unsupported_syntax',
          'Pattern assignment parsing is not yet supported.',
          token,
        );
      } else {
        checkAssignable(left, token);
      }
      values.add(
        AssignmentExpression(
          source: source,
          start: left.start,
          end: right.end,
          left: left,
          op: token.kind.assignmentOperator,
          right: right,
        ),
      );
    } else {
      values.add(
        BinaryExpression(
          source: source,
          start: left.start,
          end: right.end,
          left: left,
          op: token.kind.binaryOperator,
          right: right,
        ),
      );
    }
  }

  Expression finishExpression(int valueBase, int operatorBase) {
    ensureOperand();
    while (operators.length > operatorBase) {
      reduce();
    }
    assert(values.length == valueBase + 1);
    return values.removeLast();
  }

  void ensureOperand() {
    if (expectsOperand) {
      error('expected_expression', 'Expected an expression.', current);
      values.add(MissingExpression(source: source, offset: current.start));
      expectsOperand = false;
    }
  }

  Identifier identifier(Token token) =>
      Identifier(source: source, start: token.start, end: token.end);

  void checkAssignable(Expression expression, Token operator) {
    if (expression is! IdentifierExpression &&
        expression is! PropertyAccessExpression &&
        expression is! IndexExpression &&
        expression is! MissingExpression) {
      error(
        'invalid_assignment_target',
        'Expected an assignable expression.',
        operator,
      );
    }
  }

  void checkSelector() {
    var target = values.last;
    while (target is NullAssertionExpression) {
      target = target.operand;
    }
    if (target case UpdateExpression(isPrefix: false)) {
      error(
        'invalid_selector',
        'Parenthesize the update before accessing its result.',
        current,
      );
    }
  }

  bool isUnsupported(TokenKind kind) => switch (kind) {
    .keywordNew ||
    .keywordConst ||
    .keywordSuper ||
    .keywordThrow ||
    .keywordSwitch ||
    .leftBracket ||
    .emptyBrackets ||
    .leftBrace ||
    .stringStart ||
    .hash ||
    .cascade ||
    .nullAwareCascade ||
    .dot ||
    .arrow => true,
    _ => false,
  };

  void unexpected({bool unsupported = false}) {
    if (current.kind != .invalid) {
      error(
        unsupported ? 'unsupported_syntax' : 'unexpected_token',
        unsupported
            ? 'This syntax is not yet supported by the expression parser.'
            : 'Unexpected token in expression.',
        current,
      );
    }
    advance();
  }

  void error(String code, String message, Token token) {
    diagnostics.add(
      Diagnostic(
        code: 'parser.$code',
        severity: .error,
        message: message,
        span: SourceSpan(source, token.start, token.end),
      ),
    );
  }
}
