import 'dart:collection';

import 'package:dartc/ast.dart';
import 'package:dartc/diagnostics.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

import 'selector_tail.dart';
import 'string_sequence.dart';

part 'delimiters.dart';
part 'operators.dart';
part 'type_annotations.dart';
part 'type_expressions.dart';
part 'function_types.dart';
part 'record_types.dart';
part 'collections.dart';
part 'for_headers.dart';
part 'conditionals.dart';
part 'access_chains.dart';
part 'statements.dart';
part 'variables.dart';
part 'throw_expression.dart';
part 'parameters.dart';
part 'annotations.dart';
part 'function_bodies.dart';
part 'function_expressions.dart';
part 'readers.dart';
part 'compilation_units.dart';
part 'directives.dart';
part 'declarations.dart';
part 'type_declarations.dart';
part 'members.dart';
part 'constructors.dart';
part 'patterns.dart';
part 'pattern_collections.dart';
part 'pattern_declarations.dart';
part 'switches.dart';

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
/// forms include scalar literals, strings with interpolation and adjacency,
/// records, operators, generic calls, explicit constructor calls, type tests and
/// casts, throw expressions, super receivers, member access, indexing, cascades,
/// dot shorthands, function expressions with their own body context,
/// switch expressions, pattern assignments and collection literals with spreads,
/// null-aware elements, if/else, if-case and for/for-in headers.
/// Parsing does not resolve names or check types.
///
/// Recovery preserves the input tokens and uses zero-width [MissingExpression]
/// nodes for omitted operands. With errors, the returned node may cover only
/// part of the input.
ParseResult<Expression> parseExpression(ScanResult input) =>
    _Parser(input).parse();

sealed class _Frame(final int valueBase, final int operatorBase);

enum _ParseBoundary {
  input,
  expression,
  header,
  patternConstant,
  patternRelation,
  initializer,
}

enum _ExpressionStop { complete, conditional, syntax }

final class _Parser {
  _Parser(ScanResult input)
    : source = input.source,
      tokens = input.tokens,
      current = input.tokens.first,
      trialStart = null,
      diagnostics = [...input.diagnostics];

  _Parser.trial(_Parser parent)
    : source = parent.source,
      tokens = parent.tokens,
      cursor = parent.cursor + 1,
      current = parent.tokens[parent.cursor + 1],
      diagnostics = [],
      trialStart = parent.cursor + 1,
      functionModifier = parent.functionModifier,
      _lookahead = parent.lookahead;

  _Parser.nested(_Parser parent)
    : source = parent.source,
      tokens = parent.tokens,
      cursor = parent.cursor,
      current = parent.current,
      diagnostics = [],
      trialStart = null,
      functionModifier = parent.functionModifier,
      _lookahead = parent.lookahead;

  final SourceFile source;
  final List<Token> tokens;
  final List<Diagnostic> diagnostics;
  final List<Expression> values = [];
  final List<Token> operators = [];
  // Operator indices used as prefixes, including the ambiguous '-' token.
  final List<int> prefixes = [];
  // Operator indices awaiting ':', limited by the current delimiter's base.
  final List<int> questions = [];
  final List<_Frame> frames = [];
  final int? trialStart;
  bool initialOperatorBoundary = false;
  int cursor = 0;
  // Either tokens[cursor] or its unconsumed suffix after a closing type angle.
  Token current;
  _Lookahead? _lookahead;
  _Lookahead get lookahead => _lookahead ??= _Lookahead(tokens);
  bool expectsOperand = true;
  bool hasSyntaxError = false;
  // The last call/index chain and whether its ?[ selectors are already fixed
  // as indexes. Other primaries and selectors start a new chain.
  Expression? selectorTarget;
  bool checkedNullAware = false;
  // A terminal postfix assertion cannot be followed by a tighter selector.
  Expression? postfixTarget;
  _NullableForInitializer? nullableForInitializer;
  FunctionBodyModifier? functionModifier;
  _Reader<void>? pendingSyntax;

  bool get inAsync =>
      functionModifier == .asyncKeyword || functionModifier == .asyncStar;
  bool get inGenerator =>
      functionModifier == .syncStar || functionModifier == .asyncStar;

  int get operatorBase => frames.isEmpty ? 0 : frames.last.operatorBase;

  void advance() {
    current = tokens[++cursor];
  }

  ParseResult<Expression> parse() {
    beginExpression();
    final stop = run(trial: false);
    final node = stop == .complete
        ? finishExpression(0, 0)
        : _ExpressionReader(this, boundary: .input, stop: stop).finish();
    assert(prefixes.isEmpty && questions.isEmpty);
    return ParseResult._(node, diagnostics);
  }

  _ExpressionStop run({required bool trial, _ParseBoundary boundary = .input}) {
    while (current.kind != .eof || frames.isNotEmpty) {
      final token = current;
      final frame = frames.isEmpty ? null : frames.last;
      if (!trial && frame == null) {
        if (boundary == .header) return .complete;
        if (boundary != .input &&
            (token.kind.endsExpression ||
                token.kind == .colon && questions.isEmpty ||
                !expectsOperand &&
                    token.kind != .colon &&
                    token.kind != .cascade &&
                    token.kind != .nullAwareCascade &&
                    !token.kind.continuesExpression)) {
          return .complete;
        }
      }
      if (frame == null &&
          !expectsOperand &&
          (boundary == .patternConstant || boundary == .patternRelation)) {
        if (token.kind == .keywordAs ||
            token.kind == .keywordIs ||
            token.kind == .bang ||
            token.kind == .cascade ||
            token.kind == .nullAwareCascade ||
            token.kind.precedence != 0 &&
                token.kind.precedence <
                    (boundary == .patternRelation ? 8 : 14)) {
          return .complete;
        }
      }
      if (frame is _IfHeader && token.kind == .keywordCase) {
        frame.element.condition = finishExpression(
          frame.valueBase,
          frame.operatorBase,
        );
        advance();
        pendingSyntax = _CollectionCaseReader(this, frame);
        return .syntax;
      }
      if (frame is _Shorthand && endShorthandAtBoundary(frame)) continue;
      if (frame is _Cascade && endCascadeAtBoundary(frame)) continue;
      if (frame is _Throw && endThrowAtBoundary(frame)) continue;
      if (trial) {
        if (hasSyntaxError || token.kind == .invalid) return .complete;
        if (frames.isEmpty &&
            (token.kind == .colon && questions.isEmpty ||
                token.kind.endsExpression ||
                !expectsOperand &&
                    token.kind != .colon &&
                    !token.kind.continuesExpression)) {
          return .complete;
        }
      }
      if (token.kind == .eof ||
          token.kind == .rightParen ||
          token.kind == .rightBracket ||
          token.kind == .rightBrace ||
          token.kind == .interpolationEnd) {
        if (frames.isNotEmpty) {
          closeDelimiter();
        } else {
          unexpected();
        }
        continue;
      }
      if (frame is _ForHeader && parseForSeparator(frame)) continue;
      if (token.kind == .comma) {
        if (frame is _Collection) {
          finishCollectionElement(frame);
          advance();
        } else if (frame is _Sequence) {
          finishElement(frame);
          if (frame is _Group) frame.hasComma = true;
          advance();
        } else {
          unexpected();
        }
        continue;
      }
      if (token.kind == .colon) {
        if (frame is _Collection &&
            (questions.isEmpty || questions.last < operatorBase)) {
          parseMapKey(frame);
        } else {
          parseColon();
        }
        continue;
      }
      if (frame is _Collection) {
        if (token.kind == .keywordElse) {
          if (!finishCollectionElement(frame)) unexpected();
          continue;
        }
        if (expectsOperand && parseElementPrefix(frame)) {
          if (nullableForInitializer != null) return .conditional;
          if (pendingSyntax != null) return .syntax;
          continue;
        }
      }
      if (expectsOperand) {
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
          parseOperand(
            allowFunction:
                (boundary != .patternConstant && boundary != .initializer) ||
                frames.isNotEmpty,
          );
          if (pendingSyntax != null) return .syntax;
        }
      } else {
        if (parseContinuation()) return .conditional;
      }
    }
    return .complete;
  }

  void parseOperand({bool allowFunction = true}) {
    final token = current;
    if (parsePatternAssignment()) return;
    if (token.kind == .keywordAwait && functionModifier != null) {
      if (!inAsync) {
        error(
          'await_in_sync',
          'An await expression requires an asynchronous context.',
          token,
        );
      }
      prefixes.add(operators.length);
      operators.add(token);
      advance();
      return;
    }
    if (token.kind == .keywordAwait && tokens[cursor + 1].kind.isIdentifier) {
      error(
        'await_in_sync',
        'An await expression requires an asynchronous context.',
        token,
      );
    }
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
        case .leftBracket ||
            .emptyBrackets ||
            .emptyBracketsAssign ||
            .leftBrace:
          openCollection();
          return;
        case .keywordConst:
          switch (tokens[cursor + 1].kind) {
            case .dot:
              openShorthand();
            case .leftParen:
              advance();
              frames.add(
                _Group(
                  current,
                  values.length,
                  operators.length,
                  constKeyword: token,
                ),
              );
              advance();
            case .less ||
                .leftBracket ||
                .emptyBrackets ||
                .emptyBracketsAssign ||
                .leftBrace:
              parseCollectionPrefix();
            default:
              parseConstruction();
          }
          return;
        case .keywordNew:
          parseConstruction();
          return;
        case .keywordSwitch:
          final child = _Parser.nested(this);
          pendingSyntax = _OperandReader(
            this,
            child,
            _SwitchExpressionReader(child),
          );
          return;
        case .keywordThrow:
          openThrow();
          return;
        case .dot:
          openShorthand();
          return;
        case .less:
          if (allowFunction && parseFunctionExpression()) return;
          parseCollectionPrefix();
          return;
        case .hash:
          parseSymbol();
          return;
        case .leftParen:
          if (allowFunction && parseFunctionExpression()) return;
          frames.add(_Group(token, values.length, operators.length));
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
        case .keywordSuper:
          values.add(
            SuperExpression(source: source, start: token.start, end: token.end),
          );
        case .stringLiteral || .stringStart:
          parseStrings();
          return;
        case .invalid:
          advance();
          return;
        default:
          unexpected();
          return;
      }
    }
    advance();
    expectsOperand = false;
  }

  void parseStrings([StringSequence? sequence]) {
    StringLiteralExpression literal(Token t) =>
        StringLiteralExpression(source: source, start: t.start, end: t.end);
    if (sequence == null && current.kind == .stringLiteral) {
      final first = literal(current);
      advance();
      if (current.kind != .stringLiteral && current.kind != .stringStart) {
        values.add(first);
        expectsOperand = false;
        return;
      }
      sequence = StringSequence()..addLiteral(first);
    }
    final strings = sequence ?? StringSequence();
    while (true) {
      final token = current;
      switch (token.kind) {
        case .stringLiteral:
          strings.addLiteral(literal(token));
          advance();
        case .stringStart || .stringMiddle || .stringEnd:
          strings.addText(token);
          advance();
        case .interpolationIdentifier:
          advance();
          final name = current;
          final Expression expression;
          if (name.kind == .keywordThis) {
            expression = ThisExpression(
              source: source,
              start: name.start,
              end: name.end,
            );
          } else if (name.kind.isIdentifier) {
            expression = IdentifierExpression(
              source: source,
              start: name.start,
              end: name.end,
              identifier: identifier(name),
            );
          } else {
            error(
              'expected_identifier',
              'Expected an identifier or this.',
              name,
            );
            expression = MissingExpression(source: source, offset: name.start);
          }
          strings.addInterpolation(
            token,
            expression,
            name.end,
            isBraced: false,
          );
          advance();
        case .interpolationStart:
          frames.add(
            _Interpolation(token, values.length, operators.length, strings),
          );
          advance();
          expectsOperand = true;
          return;
        default:
          values.add(strings.finish(current.start));
          expectsOperand = false;
          return;
      }
    }
  }

  void parseSymbol() {
    final hash = current;
    advance();
    var end = current.start;
    if (current.kind.isSymbolOperator || current.kind == .keywordVoid) {
      end = current.end;
      advance();
    } else {
      while (true) {
        if (current.kind.isIdentifier) {
          end = current.end;
          advance();
        } else {
          error(
            'expected_identifier',
            'Expected a symbol name or operator.',
            current,
          );
          if (current.kind.isKeyword) {
            end = current.end;
            advance();
          }
          break;
        }
        if (current.kind != .dot) break;
        end = current.end;
        advance();
      }
    }
    values.add(
      LiteralExpression(
        source: source,
        start: hash.start,
        end: end,
        kind: .symbol,
      ),
    );
    expectsOperand = false;
  }

  bool parseContinuation() {
    final token = current;
    if (values.last is CascadeExpression &&
        token.kind != .cascade &&
        token.kind != .nullAwareCascade) {
      error(
        'invalid_cascade_continuation',
        'Parenthesize the cascade before this operation.',
        token,
      );
    }
    switch (token.kind) {
      case .cascade || .nullAwareCascade:
        openCascade();
        return false;
      case .less:
        final frame = frames.lastOrNull;
        if (tryTypeArguments()) {
          if (frame is _Shorthand) frame.pendingBang = null;
          return false;
        }
        if (frames.lastOrNull case final _Shorthand frame) {
          closeShorthand(frame);
          return false;
        }
        if (frames.lastOrNull case final _Cascade frame when !frame.assigned) {
          closeCascade(frame);
          return false;
        }
      case .keywordAs || .keywordIs:
        parseTypeOperator();
        return false;
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
        if (target is SuperExpression && token.kind == .nullAwareAccess) {
          error(
            'null_aware_super',
            "A super member access cannot use '?.'.",
            token,
            preventsConditional: false,
          );
        }
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
        return false;
      case .leftParen:
        checkSelector();
        final callee = values.removeLast();
        frames.add(
          _Call(
            token,
            values.length,
            operators.length,
            callee,
            checkedNullAware: callee == selectorTarget && checkedNullAware,
          ),
        );
        advance();
        expectsOperand = true;
        return false;
      case .leftBracket || .emptyBrackets || .emptyBracketsAssign:
        openIndex(isNullAware: false);
        return false;
      case .question:
        if (_lookahead?.conditionals[cursor]
            case final _ConditionalBranches branches
            when tokens[cursor + 1].kind != .leftBracket) {
          acceptConditional(branches);
          return false;
        }
        if (tokens[cursor + 1].kind == .leftBracket) {
          if (!(values.last == selectorTarget && checkedNullAware) &&
              cursor < lookahead.lastColon) {
            return true;
          }
          advance();
          openIndex(isNullAware: true);
          return false;
        }
      case .bang:
        final isSelector = tokens[cursor + 1].kind.followsSelectorBang;
        if (values.last == postfixTarget && isSelector) {
          if (operators.length > operatorBase &&
              prefixes.isNotEmpty &&
              prefixes.last == operators.length - 1) {
            reduce();
          } else {
            error(
              'invalid_selector',
              'Parenthesize the assertion before this selector.',
              token,
            );
          }
        }
        final operand = values.removeLast();
        checkValue(operand);
        values.add(
          NullAssertionExpression(
            source: source,
            start: operand.start,
            end: token.end,
            operand: operand,
          ),
        );
        if (frames.lastOrNull case final _Shorthand frame) {
          frame.pendingBang = values.last as NullAssertionExpression;
        }
        final frame = frames.lastOrNull;
        if (!isSelector &&
            !(frame is _Shorthand && !frame.isConst) &&
            !(frame is _Cascade && !frame.assigned)) {
          postfixTarget = values.last;
        }
        advance();
        return false;
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
        return false;
      default:
        break;
    }
    final precedence = token.kind.precedence;
    if (precedence == 0) {
      unexpected();
      return false;
    }
    reduceBefore(token);
    if (precedence == _assignmentPrecedence) {
      if (frames.lastOrNull case final _Cascade frame) frame.assigned = true;
    }
    if (token.kind == .question) questions.add(operators.length);
    operators.add(token);
    advance();
    expectsOperand = true;
    return false;
  }

  void reduceBefore(Token token) {
    final precedence = token.kind.precedence;
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
      } else if (token.kind == .keywordAwait) {
        checkValue(right);
        values.add(
          AwaitExpression(
            source: source,
            start: token.start,
            end: right.end,
            expression: right,
          ),
        );
      } else {
        if (token.kind == .bang) checkValue(right);
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
      checkValue(condition);
      checkValue(thenExpression);
      checkValue(elseExpression);
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
    checkValue(right);
    if (token.kind.precedence == _assignmentPrecedence) {
      checkAssignable(left, token);
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
      if (token.kind.precedence < _equalityPrecedence) checkValue(left);
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
    final value = values.removeLast();
    checkValue(value);
    return value;
  }

  void ensureOperand() {
    if (expectsOperand) {
      error('expected_expression', 'Expected an expression.', current);
      values.add(MissingExpression(source: source, offset: current.start));
      expectsOperand = false;
    }
  }

  Identifier identifier(Token token, {bool inType = false}) {
    if (!inType &&
        functionModifier != null &&
        (token.kind == .keywordAwait || token.kind == .keywordYield)) {
      error(
        'async_keyword_as_identifier',
        'This word cannot be an identifier in an asynchronous or generator body.',
        token,
      );
    }
    return Identifier(source: source, start: token.start, end: token.end);
  }

  void checkAssignable(Expression expression, Token operator) {
    if (expression is DotShorthandExpression) {
      expression = expression.expression;
    }
    if (expression is! IdentifierExpression &&
        expression is! PropertyAccessExpression &&
        expression is! IndexExpression &&
        expression is! CascadePropertyExpression &&
        expression is! CascadeIndexExpression &&
        expression is! MissingExpression) {
      error(
        'invalid_assignment_target',
        'Expected an assignable expression.',
        operator,
        preventsConditional: false,
      );
    }
  }

  void checkValue(Expression expression) {
    if (expression is SuperExpression) invalidSuperValue(expression);
  }

  void invalidSuperValue(SuperExpression expression) {
    error(
      'invalid_super_value',
      'Use super as a member receiver or an operator receiver.',
      Token(.keywordSuper, source, expression.start, expression.end),
      preventsConditional: false,
    );
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
        preventsConditional: false,
      );
    }
  }

  void unexpected() {
    if (current.kind != .invalid) {
      error('unexpected_token', 'Unexpected token in expression.', current);
    }
    advance();
  }

  void error(
    String code,
    String message,
    Token token, {
    bool preventsConditional = true,
  }) {
    if (preventsConditional) hasSyntaxError = true;
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
