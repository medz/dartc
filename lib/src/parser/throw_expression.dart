part of 'parser.dart';

final class _Throw(
  super.valueBase,
  super.operatorBase,
  final Token keyword,
  final bool allowCascades,
) extends _Frame;

extension on _Parser {
  void openThrow() {
    if (operators.length > operatorBase &&
        operators.last.kind.precedence != _assignmentPrecedence &&
        operators.last.kind != .question) {
      error(
        'invalid_throw_position',
        'Parenthesize the throw expression in this operand.',
        current,
      );
    }
    final parent = frames.lastOrNull;
    var allowCascades = switch (parent) {
      _Throw(:final allowCascades) => allowCascades,
      _Cascade() => false,
      null => trialStart == null,
      _ => true,
    };
    for (var i = operatorBase; i < operators.length; i++) {
      if (operators[i].kind == .question) allowCascades = false;
    }
    frames.add(_Throw(values.length, operators.length, current, allowCascades));
    advance();
  }

  bool endThrowAtBoundary(_Throw frame) {
    final kind = current.kind;
    if (kind != .eof &&
        !kind.endsExpression &&
        !(kind == .colon &&
            (questions.isEmpty || questions.last < frame.operatorBase)) &&
        !(!frame.allowCascades &&
            (kind == .cascade || kind == .nullAwareCascade))) {
      return false;
    }
    final expression = finishExpression(frame.valueBase, frame.operatorBase);
    frames.removeLast();
    values.add(
      ThrowExpression(
        source: source,
        start: frame.keyword.start,
        end: expression.end,
        expression: expression,
      ),
    );
    expectsOperand = false;
    return true;
  }
}
