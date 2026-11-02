part of 'parser.dart';

sealed class _Delimiter(
  final Token opening,
  super.valueBase,
  super.operatorBase,
) extends _Frame {
  TokenKind get closing;
}

sealed class _Sequence(super.opening, super.valueBase, super.operatorBase)
    extends _Delimiter {
  int? name;

  @override
  TokenKind get closing => .rightParen;
}

final class _Group(
  super.opening,
  super.valueBase,
  super.operatorBase, {
  final Token? constKeyword,
}) extends _Sequence {
  final List<int> fields = [];
  bool hasComma = false;
}

sealed class _Arguments(super.opening, super.valueBase, super.operatorBase)
    extends _Sequence {
  final List<int> arguments = [];
}

final class _ArgumentList(super.opening, super.valueBase, super.operatorBase)
    extends _Arguments {
  late int result;
}

final class _Call(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final int callee, {
  final int? typeArguments,
  final bool checkedNullAware = false,
}) extends _Arguments;

final class _Construction(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Token keyword,
  final List<int> components,
  final int? typeArguments,
  final int? constructorName,
) extends _Arguments;

final class _Index(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final int target, {
  required final bool isNullAware,
  required final bool checkedNullAware,
}) extends _Delimiter {
  @override
  TokenKind get closing => .rightBracket;
}

final class _Interpolation(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final StringSequence strings,
) extends _Delimiter {
  @override
  TokenKind get closing => .interpolationEnd;
}

extension on _Parser {
  void openIndex({required bool isNullAware}) {
    checkSelector();
    final token = current;
    final target = values.removeLast();
    final checked = target == selectorTarget ? checkedNullAware : isNullAware;
    if (isNullAware &&
        (arena.hasKind(target, .castExpression) ||
            arena.hasKind(target, .typeTestExpression))) {
      values.add(target);
      checkTypeContinuation(current);
      values.removeLast();
    }
    if (token.kind == .emptyBrackets || token.kind == .emptyBracketsAssign) {
      error('expected_expression', 'Expected an index expression.', token);
      values.add(
        arena.putIndexExpression(
          start: arena.rStart(target),
          end: token.start + 2,
          target: target,
          index: arena.putMissingExpression(offset: token.start + 1),
          isNullAware: isNullAware,
        ),
      );
      consumeEmptyBrackets();
      return;
    }
    advance();
    frames.add(
      _Index(
        token,
        values.length,
        operators.length,
        target,
        isNullAware: isNullAware,
        checkedNullAware: checked,
      ),
    );
    expectsOperand = true;
  }

  void finishElement(_Sequence frame) {
    final value = finishExpression(frame.valueBase, frame.operatorBase);
    final name = frame.name;
    switch (frame) {
      case _Arguments():
        frame.arguments.add(
          arena.putArgument(
            start: arena.rStartOrNull(name) ?? arena.rStart(value),
            end: arena.rEnd(value),
            name: name,
            value: value,
          ),
        );
      case _Group():
        frame.fields.add(
          name == null
              ? value
              : arena.putNamedRecordField(
                  start: arena.rStart(name),
                  end: arena.rEnd(value),
                  name: name,
                  value: value,
                ),
        );
    }
    frame.name = null;
    expectsOperand = true;
  }

  void closeDelimiter() {
    final frame = frames.last as _Delimiter;
    final matched = current.kind == frame.closing;
    final end = matched ? current.end : current.start;
    if (!matched) {
      error(
        'expected_closer',
        "Expected '${frame.closing.spelling}'.",
        current,
      );
    }
    final int expression;
    switch (frame) {
      case _CascadeIndex():
        expression = arena.putCascadeIndexExpression(
          start: frame.marker.start,
          end: end,
          index: finishExpression(frame.valueBase, frame.operatorBase),
        );
      case _Interpolation():
        frame.strings.addInterpolation(
          frame.opening,
          finishExpression(frame.valueBase, frame.operatorBase),
          end,
          isBraced: true,
        );
        frames.removeLast();
        if (matched) advance();
        parseStrings(frame.strings);
        return;
      case _IfHeader():
        frame.element.condition = finishExpression(
          frame.valueBase,
          frame.operatorBase,
        );
        frames.removeLast();
        expectsOperand = true;
        if (matched) advance();
        return;
      case _ForHeader():
        final parts = closeForHeader(frame);
        switch (frame) {
          case _ForElementHeader():
            if (frame.element.isAwait && !arena.hasKind(parts, .forInParts)) {
              error(
                'invalid_await_for',
                'An await-for requires a for-in header.',
                frame.element.token,
              );
            }
            frame.element.parts = parts;
          case _ForStatementHeader():
            frame.parts = parts;
        }
        frames.removeLast();
        expectsOperand = true;
        if (matched) advance();
        return;
      case _Collection():
        expression = closeCollection(frame, end);
      case _Index():
        final index = finishExpression(frame.valueBase, frame.operatorBase);
        expression = arena.putIndexExpression(
          start: arena.rStart(frame.target),
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
        if (frame
            case _Group(
              constKeyword: final Token keyword,
              fields: [final entry],
              hasComma: false,
            )
            when arena.isExpression(entry)) {
          error(
            'expected_record_comma',
            'A record with one positional field needs a trailing comma.',
            keyword,
          );
        }
        switch (frame) {
          case _ArgumentList():
            frame.result = arena.putArgumentList(
              start: frame.opening.start,
              end: end,
              arguments: frame.arguments,
            );
            frames.removeLast();
            if (matched) advance();
            return;
          case _Call():
            expression = arena.putInvocationExpression(
              start: arena.rStart(frame.callee),
              end: end,
              callee: frame.callee,
              typeArguments: frame.typeArguments,
              arguments: arena.putArgumentList(
                start: frame.opening.start,
                end: end,
                arguments: frame.arguments,
              ),
            );
          case _Construction():
            expression = arena.putInstanceCreationExpression(
              start: frame.keyword.start,
              end: end,
              kind: frame.keyword.kind == .keywordConst
                  ? .constKeyword
                  : .newKeyword,
              name: frame.components,
              typeArguments: frame.typeArguments,
              constructorName: frame.constructorName,
              arguments: arena.putArgumentList(
                start: frame.opening.start,
                end: end,
                arguments: frame.arguments,
              ),
            );
          case _ConstShorthand():
            expression = arena.putConstDotShorthandExpression(
              start: frame.keyword.start,
              end: end,
              name: frame.member,
              typeArguments: frame.typeArguments,
              arguments: arena.putArgumentList(
                start: frame.opening.start,
                end: end,
                arguments: frame.arguments,
              ),
            );
          case _Group(
                fields: [final value],
                hasComma: false,
                constKeyword: null,
              )
              when arena.isExpression(value):
            expression = arena.putParenthesizedExpression(
              start: frame.opening.start,
              end: end,
              expression: value,
            );
          case _Group():
            expression = arena.putRecordExpression(
              start: frame.constKeyword?.start ?? frame.opening.start,
              end: end,
              hasConstKeyword: frame.constKeyword != null,
              fields: frame.fields,
            );
        }
    }
    frames.removeLast();
    values.add(expression);
    switch (frame) {
      case _Call(:final checkedNullAware, :final callee)
          when !arena.hasKind(callee, .identifierExpression) &&
              !arena.hasKind(callee, .propertyAccessExpression) &&
              !arena.hasKind(callee, .thisExpression) &&
              !arena.hasKind(callee, .superExpression) &&
              !arena.hasKind(callee, .dotShorthandReferenceExpression):
        selectorTarget = expression;
        this.checkedNullAware = checkedNullAware;
      case _Index(:final checkedNullAware):
        selectorTarget = expression;
        this.checkedNullAware = checkedNullAware;
      case _CascadeIndex():
        selectorTarget = expression;
        checkedNullAware = false;
      default:
        break;
    }
    expectsOperand = false;
    if (matched) advance();
  }
}
