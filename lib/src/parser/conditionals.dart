part of 'parser.dart';

sealed class _QuestionResolution;

final class _ConditionalBranches(
  final int thenBranch,
  final int elseBranch,
  final List<Diagnostic> diagnostics,
  final int cursor,
  final Token current,
) implements _QuestionResolution;

final class _ConditionalTrial(_Parser parent, int question) {
  final _Parser reader = _Parser.trial(parent, question);
  int? thenBranch;
  bool? inherits;
  bool tracked = false;
  int colon = -1;
  int thenDiagnostics = 0;
}

final class _ConditionalReader(final _Parser parent)
    extends _Reader<_QuestionResolution?> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final trials = [_ConditionalTrial(parent, parent.cursor)];
    while (trials.isNotEmpty) {
      final trial = trials.last;
      final reader = trial.reader;
      final stop = reader.nullableForInitializer == null
          ? reader.run(trial: true)
          : _ExpressionStop.conditional;
      if (stop == .syntax) {
        final syntax = reader.pendingSyntax!;
        reader.pendingSyntax = null;
        yield syntax;
        continue;
      }
      if (stop == .conditional) {
        trial.inherits = trial.thenBranch == null
            ? reader.indexContinuation()
            : null;
        trial.tracked =
            reader.values.isNotEmpty &&
            reader.values.last == reader.selectorTarget;
        trials.add(_ConditionalTrial(reader, reader.cursor));
        continue;
      }
      _ConditionalBranches? branches;
      int? head = trial.thenBranch;
      if (!reader.hasSyntaxError && reader.current.kind != .invalid) {
        final expression = reader.finishExpression(0, 0);
        if (!reader.hasSyntaxError) {
          if (trial.thenBranch case final first?) {
            branches = _ConditionalBranches(
              first,
              expression,
              reader.diagnostics,
              reader.cursor,
              reader.current,
            );
          } else {
            head = expression;
            if (reader.current.kind == .colon) {
              trial.thenBranch = expression;
              trial.colon = reader.cursor;
              trial.thenDiagnostics = reader.diagnostics.length;
              reader.advance();
              reader.expectsOperand = true;
              continue;
            }
          }
        }
      }
      _QuestionResolution? outcome = branches;
      var first = trials.length - 1;
      final list = reader.leadingList;
      if (first != 0 &&
          list != null &&
          _selectorLink(reader.arena, head, list) != null) {
        while (first > 0 && trials[first - 1].inherits != null) {
          first--;
        }
        if (first < trials.length - 1) {
          final arms = <_ElseArm>[];
          if (branches != null) {
            arms.add(
              _ElseArm(
                trial.colon,
                branches.elseBranch,
                branches.diagnostics.sublist(trial.thenDiagnostics),
                branches.cursor,
                branches.current,
              ),
            );
            while (arms.last.current.kind == .colon &&
                arms.length < trials.length - first) {
              final colon = arms.last.cursor;
              final arm = _BranchExpression(_Parser.trial(parent, colon));
              yield arm;
              if (arm.result == null) break;
              arms.add(
                _ElseArm(
                  colon,
                  arm.result!,
                  arm.parser.diagnostics,
                  arm.parser.cursor,
                  arm.parser.current,
                ),
              );
            }
          }
          outcome = _IndexSequence.reduce(trials, first, arms);
          trials.removeRange(first + 1, trials.length);
        }
      }
      trials.removeLast();
      if (trials.isEmpty) {
        result = outcome;
        return;
      }
      trials.last.reader.acceptConditional(outcome);
    }
  }
}

// A branch ends at a grammar boundary, including the colon of its caller.
final class _BranchExpression(final _Parser parser) extends _Reader<int?> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    while (true) {
      final stop = parser.nullableForInitializer == null
          ? parser.run(trial: true)
          : _ExpressionStop.conditional;
      if (stop == .syntax) {
        final syntax = parser.pendingSyntax!;
        parser.pendingSyntax = null;
        yield syntax;
      } else if (stop == .conditional) {
        final choice = _ConditionalReader(parser);
        yield choice;
        parser.acceptConditional(choice.result);
      } else {
        result = null;
        if (!parser.hasSyntaxError && parser.current.kind != .invalid) {
          final value = parser.finishExpression(0, 0);
          if (!parser.hasSyntaxError) result = value;
        }
        return;
      }
    }
  }
}

final class _ChosenConditional(
  final _Parser parent,
  final _IndexSequence sequence,
  final _ElseArm arm,
) extends _Reader<void> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final child = _Parser.trial(parent, parent.cursor);
    if (!sequence.isDone) {
      child.indexSequences = [sequence];
    }
    final then = _BranchExpression(child);
    yield then;
    if (then.result != null &&
        child.cursor == arm.colon &&
        child.current.kind == .colon) {
      child.diagnostics.addAll(arm.diagnostics);
      parent.acceptConditional(
        _ConditionalBranches(
          then.result!,
          arm.value,
          child.diagnostics,
          arm.cursor,
          arm.current,
        ),
      );
    } else if (then.result != null && child.current.kind == .colon) {
      final other = _BranchExpression(_Parser.trial(child, child.cursor));
      yield other;
      if (other.result case final expression?) {
        child.diagnostics.addAll(other.parser.diagnostics);
        parent.acceptConditional(
          _ConditionalBranches(
            then.result!,
            expression,
            child.diagnostics,
            other.parser.cursor,
            other.parser.current,
          ),
        );
      } else {
        parent.acceptConditional(null);
      }
    } else {
      parent.acceptConditional(null);
    }
  }
}

extension on _Parser {
  void acceptConditional(_QuestionResolution? outcome) {
    if (outcome is _IndexSequence) {
      (indexSequences ??= []).add(outcome);
      return;
    }
    final result = outcome as _ConditionalBranches?;
    if (nullableForInitializer case final checkpoint?) {
      nullableForInitializer = null;
      if (result != null) {
        checkpoint.frame.declarations = null;
        pendingBranches = (cursor, result);
        cursor = checkpoint.start;
        current = tokens[cursor];
      } else {
        cursor = checkpoint.declarationEnd;
        current = checkpoint.remainder;
      }
      return;
    }
    if (result != null) {
      prepareConditional();
      reduceBefore(current);
      final condition = values.removeLast();
      checkValue(condition);
      diagnostics.addAll(result.diagnostics);
      values.add(
        arena.putConditionalExpression(
          start: arena.rStart(condition),
          end: arena.rEnd(result.elseBranch),
          condition: condition,
          thenExpression: result.thenBranch,
          elseExpression: result.elseBranch,
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
  bool get endsExpression => (_grammar[index] & 32) != 0;

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
