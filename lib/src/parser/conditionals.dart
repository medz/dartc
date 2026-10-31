part of 'parser.dart';

// Lookahead belongs to one token stream, including its speculative cursors.
final class _Lookahead(final List<Token> tokens) {
  late final int lastTypeArgumentCloser = tokens.lastIndexWhere(
    (token) => token.kind.closesTypeArgumentList,
  );
  late final int lastColon = tokens.lastIndexWhere((t) => t.kind == .colon);
  late final Map<int, (TypeArgumentList, int, Token)?> typeArguments = {};
  late final Map<int, _ConditionalResult> conditionals = {};
  late final Map<int, _IndexContent> indexContents = {};
  late final Map<int, _IndexRun> indexRuns = {};
  late final Map<int, SelectorTail> selectorTails = {};

  _IndexRun? indexRun(int start) {
    final pending = <(int, _IndexContent)>[];
    var cursor = start;
    var tail = indexRuns[cursor];
    while (tail == null &&
        tokens[cursor].kind == .question &&
        tokens[cursor + 1].kind == .leftBracket) {
      final content = indexContents[cursor + 1];
      if (content == null) return null;
      pending.add((cursor, content));
      cursor = content.cursor;
      tail = indexRuns[cursor];
    }
    final selectors = tail?.selectors ?? selectorTails[cursor];
    final end = tail?.cursor ?? selectors?.cursor ?? cursor;
    for (var i = pending.length - 1; i >= 0; i--) {
      final (question, content) = pending[i];
      tail = _IndexRun(content, tail, end, selectors);
      indexRuns[question] = tail;
    }
    return tail;
  }
}

// Only a single expression with no trailing comma is also valid index syntax.
final class _IndexContent(
  final Expression expression,
  final int end,
  final int cursor,
  final List<Diagnostic> diagnostics,
);

// Suffixes share their tails; the receiver is supplied only after selection.
final class _IndexRun(
  final _IndexContent content,
  final _IndexRun? next,
  final int cursor,
  final SelectorTail? selectors,
);

sealed class _Branch(final List<Diagnostic> diagnostics) {
  Expression materialize(List<Diagnostic> destination);
}

final class _ParsedBranch(final Expression expression, super.diagnostics)
    extends _Branch {
  @override
  Expression materialize(List<Diagnostic> destination) {
    destination.addAll(diagnostics);
    return expression;
  }
}

final class _IndexedBranch(
  final Expression receiver,
  final _IndexRun suffix,
  super.diagnostics,
) extends _Branch {
  @override
  Expression materialize(List<Diagnostic> destination) {
    destination.addAll(diagnostics);
    var expression = receiver;
    for (_IndexRun? run = suffix; run != null; run = run.next) {
      final content = run.content;
      destination.addAll(content.diagnostics);
      expression = IndexExpression(
        source: receiver.source,
        start: receiver.start,
        end: content.end,
        target: expression,
        index: content.expression,
        isNullAware: true,
      );
    }
    return suffix.selectors?.apply(expression) ?? expression;
  }
}

sealed class _ConditionalResult;

enum _NotConditional implements _ConditionalResult { invalid, stableFailure }

final class _ConditionalBranches(
  final _Branch thenBranch,
  final _Branch elseBranch,
  final int cursor,
  final Token current,
) implements _ConditionalResult;

final class _ConditionalTrial(final _Parser parent) {
  final int question = parent.cursor;
  final _Parser reader = _Parser.trial(parent);
  _Branch? thenBranch;

  _ConditionalResult? finishBranch(_Branch branch) {
    if (thenBranch == null) {
      if (branch is _ParsedBranch) reader.cacheSelectorTail(branch);
      if (reader.current.kind != .colon) return reader.conditionalFailure;
      thenBranch = branch;
      reader.advance();
      reader.expectsOperand = true;
      return null;
    }
    return _ConditionalBranches(
      thenBranch!,
      branch,
      reader.cursor,
      reader.current,
    );
  }
}

extension on _Parser {
  void cacheSelectorTail(_ParsedBranch branch) {
    if (branch.diagnostics.isNotEmpty) return;
    final content = lookahead.indexContents[trialStart];
    if (content == null ||
        lookahead.selectorTails.containsKey(content.cursor)) {
      return;
    }
    final tail = SelectorTail.capture(
      branch.expression,
      receiverStart: tokens[trialStart!].start,
      receiverEnd: content.end,
      cursor: cursor,
      current: current,
    );
    if (tail != null) lookahead.selectorTails[content.cursor] = tail;
  }

  void parseWithTrials({_ParseBoundary boundary = .input}) {
    do {
      acceptConditional(lookahead.conditionals[cursor] ?? resolveConditional());
    } while (run(trial: false, boundary: boundary));
  }

  _ConditionalResult resolveConditional() {
    final initial = _ConditionalTrial(this);
    var parser = initial.reader;
    final trials = [initial];
    while (true) {
      _ConditionalResult? result;
      if (parser.run(trial: true)) {
        final cached = parser.lookahead.conditionals[parser.cursor];
        if (cached == null) {
          final trial = _ConditionalTrial(parser);
          trials.add(trial);
          parser = trial.reader;
          continue;
        }
        result = parser.resumeConditional(
          cached,
          trials.isEmpty ? null : trials.last,
        );
        if (result == null) continue;
      } else {
        final trial = trials.last;
        if (parser.hasSyntaxError || parser.current.kind == .invalid) {
          result = trial.thenBranch == null
              ? _NotConditional.invalid
              : parser.conditionalFailure;
        } else {
          final expression = parser.finishExpression(0, 0);
          if (parser.hasSyntaxError) {
            result = trial.thenBranch == null
                ? _NotConditional.invalid
                : parser.conditionalFailure;
          } else {
            result = trial.finishBranch(
              _ParsedBranch(expression, parser.takeDiagnostics()),
            );
            if (result == null) continue;
          }
        }
      }
      while (result != null) {
        final trial = trials.removeLast();
        parser = trial.parent;
        parser.lookahead.conditionals[trial.question] = result;
        if (trials.isEmpty) return result;
        result = parser.resumeConditional(
          result,
          trials.isEmpty ? null : trials.last,
        );
      }
    }
  }

  _NotConditional get conditionalFailure => initialOperatorBoundary
      ? _NotConditional.stableFailure
      : _NotConditional.invalid;

  List<Diagnostic> takeDiagnostics() {
    if (diagnostics.isEmpty) return const [];
    final result = List<Diagnostic>.of(diagnostics);
    diagnostics.clear();
    return result;
  }

  _ConditionalResult? resumeConditional(
    _ConditionalResult result,
    _ConditionalTrial? trial,
  ) {
    if (trial != null && frames.isEmpty) {
      if (trial.thenBranch == null) {
        // Only an operator boundary preserves a failed trial when its leading
        // list becomes an index. Selector chains can instead release a colon.
        if (result == _NotConditional.stableFailure) return conditionalFailure;
        // The selected inner conditional ends this first branch without a
        // colon. Its AST would be discarded by the enclosing trial.
        if (result is _ConditionalBranches && result.current.kind != .colon) {
          return questions.isEmpty
              ? conditionalFailure
              : _NotConditional.invalid;
        }
      }
      if (result is _NotConditional) {
        final branch = indexedBranch();
        if (branch != null) return trial.finishBranch(branch);
      }
    }
    acceptConditional(result);
    return null;
  }

  _IndexedBranch? indexedBranch() {
    if (operators.isNotEmpty || values.length != 1 || hasSyntaxError) {
      return null;
    }
    final receiver = values.single;
    if (receiver == selectorTarget && !checkedNullAware ||
        receiver is CastExpression ||
        receiver is TypeTestExpression) {
      return null;
    }
    final run = lookahead.indexRun(cursor);
    if (run == null) return null;
    final next = run.selectors?.current ?? tokens[run.cursor];
    if (next.kind == .invalid ||
        next.kind != .colon &&
            !next.kind.endsExpression &&
            next.kind.continuesExpression) {
      return null;
    }
    // Match the ordinary index path, including its diagnostic token.
    advance();
    checkSelector();
    values.clear();
    cursor = run.cursor;
    current = next;
    return _IndexedBranch(receiver, run, takeDiagnostics());
  }

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
      prepareConditional();
      reduceBefore(current);
      final condition = values.removeLast();
      checkValue(condition);
      final thenExpression = result.thenBranch.materialize(diagnostics);
      final elseExpression = result.elseBranch.materialize(diagnostics);
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
      cursor = result.cursor;
      current = result.current;
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
    .interpolationEnd ||
    .keywordElse ||
    .keywordIn ||
    .keywordCase ||
    .keywordIf ||
    .keywordWhile ||
    .keywordDo ||
    .keywordFor ||
    .keywordSwitch ||
    .keywordReturn ||
    .keywordBreak ||
    .keywordContinue ||
    .keywordRethrow ||
    .keywordTry ||
    .keywordCatch ||
    .keywordFinally ||
    .keywordAssert ||
    .keywordVar ||
    .keywordFinal => true,
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
