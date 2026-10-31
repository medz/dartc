part of 'parser.dart';

sealed class _Delimiter(
  final Token opening,
  final int valueBase,
  final int operatorBase,
) {
  TokenKind get closing;
}

sealed class _Sequence(super.opening, super.valueBase, super.operatorBase)
    extends _Delimiter {
  Identifier? name;

  @override
  TokenKind get closing => .rightParen;
}

final class _Group(super.opening, super.valueBase, super.operatorBase)
    extends _Sequence {
  final List<RecordField> fields = [];
  bool hasComma = false;
}

final class _Call(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Expression callee, {
  final TypeArgumentList? typeArguments,
}) extends _Sequence {
  final List<Argument> arguments = [];
}

final class _Index(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Expression target, {
  required final bool isNullAware,
}) extends _Delimiter {
  @override
  TokenKind get closing => .rightBracket;
}

extension on _Parser {
  void openIndex({required bool isNullAware}) {
    checkSelector();
    final token = current;
    final target = values.removeLast();
    advance();
    if (token.kind == .emptyBrackets) {
      error('expected_expression', 'Expected an index expression.', token);
      values.add(
        IndexExpression(
          source: source,
          start: target.start,
          end: token.end,
          target: target,
          index: MissingExpression(source: source, offset: token.start + 1),
          isNullAware: isNullAware,
        ),
      );
      return;
    }
    delimiters.add(
      _Index(
        token,
        values.length,
        operators.length,
        target,
        isNullAware: isNullAware,
      ),
    );
    expectsOperand = true;
  }

  void finishElement(_Sequence frame) {
    final value = finishExpression(frame.valueBase, frame.operatorBase);
    final name = frame.name;
    switch (frame) {
      case _Call():
        frame.arguments.add(
          Argument(
            source: source,
            start: name?.start ?? value.start,
            end: value.end,
            name: name,
            value: value,
          ),
        );
      case _Group():
        frame.fields.add(
          name == null
              ? value
              : NamedRecordField(
                  source: source,
                  start: name.start,
                  end: value.end,
                  name: name,
                  value: value,
                ),
        );
    }
    frame.name = null;
    expectsOperand = true;
  }

  void closeDelimiter() {
    final frame = delimiters.last;
    final matched = current.kind == frame.closing;
    final end = matched ? current.end : current.start;
    if (!matched) {
      error(
        'expected_closer',
        "Expected '${frame.closing.spelling}'.",
        current,
      );
    }
    final Expression expression;
    switch (frame) {
      case _Index():
        final index = finishExpression(frame.valueBase, frame.operatorBase);
        expression = IndexExpression(
          source: source,
          start: frame.target.start,
          end: end,
          target: frame.target,
          index: index,
          isNullAware: frame.isNullAware,
        );
      case _Sequence():
        if (values.length > frame.valueBase ||
            operators.length > frame.operatorBase ||
            frame.name != null) {
          finishElement(frame);
        }
        expression = switch (frame) {
          _Call() => InvocationExpression(
            source: source,
            start: frame.callee.start,
            end: end,
            callee: frame.callee,
            typeArguments: frame.typeArguments,
            arguments: ArgumentList(
              source: source,
              start: frame.opening.start,
              end: end,
              arguments: frame.arguments,
            ),
          ),
          _Group(fields: [final Expression value], hasComma: false) =>
            ParenthesizedExpression(
              source: source,
              start: frame.opening.start,
              end: end,
              expression: value,
            ),
          _Group() => RecordExpression(
            source: source,
            start: frame.opening.start,
            end: end,
            fields: frame.fields,
          ),
        };
    }
    delimiters.removeLast();
    values.add(expression);
    expectsOperand = false;
    if (matched) advance();
  }
}
