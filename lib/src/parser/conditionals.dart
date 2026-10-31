part of 'parser.dart';

// Lookahead belongs to one token stream, including its speculative cursors.
final class _Lookahead(final List<Token> tokens) {
  late final int lastTypeArgumentCloser = tokens.lastIndexWhere(
    (token) => token.kind.closesTypeArgumentList,
  );
  late final int lastColon = tokens.lastIndexWhere((t) => t.kind == .colon);
  late final Map<int, (TypeArgumentList, int, Token)?> typeArguments = {};
  late final Map<int, _ConditionalResult> conditionals = {};
}

sealed class _ConditionalResult;

enum _NotConditional implements _ConditionalResult { invalid, stableFailure }

final class _ConditionalBranches(
  final Expression thenExpression,
  final Expression elseExpression,
  final int cursor,
  final Token current,
  final List<Diagnostic> diagnostics,
) implements _ConditionalResult;

final class _ConditionalTrial(final _Parser parent) {
  final int question = parent.cursor;
  final _Parser reader = _Parser.trial(parent);
  Expression? thenExpression;
}

extension on _Parser {
  void parseWithTrials() {
    final initial = _ConditionalTrial(this);
    var parser = initial.reader;
    final trials = [initial];
    while (true) {
      _ConditionalResult result;
      if (parser.run(trial: parser != this)) {
        final cached = parser.lookahead.conditionals[parser.cursor];
        if (cached == null) {
          final trial = _ConditionalTrial(parser);
          trials.add(trial);
          parser = trial.reader;
          continue;
        }
        if (cached != _NotConditional.stableFailure ||
            trials.isEmpty ||
            trials.last.thenExpression != null ||
            parser.delimiters.isNotEmpty) {
          parser.acceptConditional(cached);
          continue;
        }
        result = parser.conditionalFailure;
      } else {
        if (parser == this) return;
        final trial = trials.last;
        if (parser.hasSyntaxError || parser.current.kind == .invalid) {
          result = trial.thenExpression == null
              ? _NotConditional.invalid
              : parser.conditionalFailure;
        } else {
          final expression = parser.finishExpression(0, 0);
          if (parser.hasSyntaxError) {
            result = trial.thenExpression == null
                ? _NotConditional.invalid
                : parser.conditionalFailure;
          } else if (trial.thenExpression == null) {
            if (parser.current.kind == .colon) {
              trial.thenExpression = expression;
              parser.advance();
              parser.expectsOperand = true;
              continue;
            }
            result = parser.conditionalFailure;
          } else {
            result = _ConditionalBranches(
              trial.thenExpression!,
              expression,
              parser.cursor,
              parser.current,
              parser.diagnostics,
            );
          }
        }
      }
      while (true) {
        final trial = trials.removeLast();
        parser = trial.parent;
        parser.lookahead.conditionals[trial.question] = result;
        // Replacing the leading list with an index must end at an operator.
        // Otherwise it can change how a subsequent ?[ selector is parsed and
        // release a colon that the trial consumed. Delimiters and else branches
        // also change the expression boundary, so they are resumed normally.
        if (result == _NotConditional.stableFailure &&
            trials.isNotEmpty &&
            trials.last.thenExpression == null &&
            parser.delimiters.isEmpty) {
          result = parser.conditionalFailure;
          continue;
        }
        parser.acceptConditional(result);
        break;
      }
    }
  }

  _NotConditional get conditionalFailure => initialOperatorBoundary
      ? _NotConditional.stableFailure
      : _NotConditional.invalid;

  void acceptConditional(_ConditionalResult result) {
    if (nullableForInitializer case final checkpoint?) {
      nullableForInitializer = null;
      if (result is _ConditionalBranches) {
        checkpoint.frame.declarations = null;
        cursor = checkpoint.start;
        current = tokens[cursor];
      } else {
        cursor = checkpoint.declarationEnd;
        current = checkpoint.remainder;
      }
      return;
    }
    if (result case _ConditionalBranches()) {
      reduceBefore(current);
      final condition = values.removeLast();
      values.add(
        ConditionalExpression(
          source: source,
          start: condition.start,
          end: result.elseExpression.end,
          condition: condition,
          thenExpression: result.thenExpression,
          elseExpression: result.elseExpression,
        ),
      );
      cursor = result.cursor;
      current = result.current;
      diagnostics.addAll(result.diagnostics);
      expectsOperand = false;
    } else {
      advance();
      openIndex(isNullAware: true);
    }
  }
}

extension on TokenKind {
  bool get closesTypeArgumentList => switch (this) {
    .greater ||
    .greaterEqual ||
    .shiftRight ||
    .shiftRightAssign ||
    .unsignedShiftRight ||
    .unsignedShiftRightAssign => true,
    _ => false,
  };

  bool get endsExpression => switch (this) {
    .comma ||
    .semicolon ||
    .rightParen ||
    .rightBracket ||
    .rightBrace ||
    .keywordElse ||
    .keywordIn ||
    .keywordCase => true,
    _ => false,
  };

  bool get continuesExpression =>
      precedence != 0 ||
      this == .keywordAs ||
      this == .keywordIs ||
      this == .dot ||
      this == .nullAwareAccess ||
      this == .leftParen ||
      this == .leftBracket ||
      this == .emptyBrackets ||
      this == .emptyBracketsAssign ||
      this == .bang ||
      this == .increment ||
      this == .decrement;
}
