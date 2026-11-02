part of 'parser.dart';

// The operator stream of an unresolved expression, consumed in source order.
final class _IndexSequence implements _QuestionResolution {
  _IndexSequence.reduce(
    List<_ConditionalTrial> trials,
    int first,
    this.operands,
  ) : _code = trials.last.reader.tokens.length <= 0x7fffffff
          ? Int32List((trials.length - first) * 2)
          : Int64List((trials.length - first) * 2) {
    // Counts of else arms consumed by the suffix under each receiver state.
    var fresh = 0, unchecked = 0, checked = 0;
    for (var i = trials.length - 1; i >= first; i--) {
      final trial = trials[i];
      final afterList = trial.tracked ? unchecked : fresh;
      final afterChecked = trial.inherits == true ? checked : afterList;
      final afterUnchecked = trial.inherits == true ? unchecked : afterList;
      final slot = (i - first) * 2;
      _code[slot] = trial.reader.trialStart! - 1;
      if (afterList < operands.length) {
        _code[slot + 1] = afterList;
        fresh = unchecked = afterList + 1;
      } else {
        _code[slot + 1] = -1;
        fresh = afterChecked;
        unchecked = afterUnchecked;
      }
      checked = afterChecked;
    }
  }

  final List<int> _code;
  final List<_ElseArm> operands;
  int _next = 0;

  int get question => _code[_next];
  bool get isDone => _next == _code.length;

  _ElseArm? take() {
    final arm = _code[_next + 1];
    _next += 2;
    return arm < 0 ? null : operands[arm];
  }
}

final class _ElseArm(
  final int colon,
  final int value,
  final List<Diagnostic> diagnostics,
  final int cursor,
  final Token current,
);

extension on _Parser {
  bool? indexContinuation() {
    final list = leadingList;
    if (list == null ||
        frames.isNotEmpty ||
        hasSyntaxError ||
        questions.isNotEmpty ||
        nullableForInitializer != null ||
        current.kind != .question ||
        tokens[cursor + 1].kind != .leftBracket ||
        values.isEmpty) {
      return null;
    }
    if (operators.isEmpty && values.length == 1) {
      return _selectorLink(arena, values.single, list);
    }
    if (operators.any((op) => !op.kind.independentInfix)) return null;
    return _selectorLink(arena, values.first, list) != null && values.length > 1
        ? false
        : null;
  }
}

// A property or postfix assertion starts a fresh receiver for the next '?['.
bool? _selectorLink(AstArena arena, int? expression, int list) {
  var inherits = true;
  while (expression != null) {
    switch (arena.kindAt(expression)) {
      case .binaryExpression ||
          .castExpression ||
          .typeTestExpression ||
          .propertyAccessExpression ||
          .nullAssertionExpression:
        inherits = false;
      case .invocationExpression || .typeInstantiationExpression:
        break;
      case .indexExpression when !arena.indexIsNullAware(expression):
        break;
      default:
        return expression == list ? inherits : null;
    }
    expression = arena.childIndex(expression, 0);
  }
  return null;
}

extension on TokenKind {
  bool get independentInfix => switch (this) {
    .plus ||
    .minus ||
    .star ||
    .slash ||
    .percent ||
    .ampersand ||
    .bar ||
    .caret ||
    .truncateDivide ||
    .shiftLeft ||
    .shiftRight ||
    .unsignedShiftRight ||
    .logicalAnd ||
    .logicalOr ||
    .ifNull => true,
    _ => false,
  };
}
