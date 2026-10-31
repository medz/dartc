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
  Identifier? name;

  @override
  TokenKind get closing => .rightParen;
}

final class _Group(
  super.opening,
  super.valueBase,
  super.operatorBase, {
  final Token? constKeyword,
}) extends _Sequence {
  final List<RecordField> fields = [];
  bool hasComma = false;
}

sealed class _Arguments(super.opening, super.valueBase, super.operatorBase)
    extends _Sequence {
  final List<Argument> arguments = [];
}

final class _ArgumentList(super.opening, super.valueBase, super.operatorBase)
    extends _Arguments {
  late ArgumentList result;
}

final class _Call(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Expression callee, {
  final TypeArgumentList? typeArguments,
  final bool checkedNullAware = false,
}) extends _Arguments;

final class _Construction(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Token keyword,
  final List<Identifier> components,
  final TypeArgumentList? typeArguments,
  final Identifier? constructorName,
) extends _Arguments;

final class _Index(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Expression target, {
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
        (target is CastExpression || target is TypeTestExpression)) {
      values.add(target);
      checkTypeContinuation(current);
      values.removeLast();
    }
    if (token.kind == .emptyBrackets || token.kind == .emptyBracketsAssign) {
      error('expected_expression', 'Expected an index expression.', token);
      values.add(
        IndexExpression(
          source: source,
          start: target.start,
          end: token.start + 2,
          target: target,
          index: MissingExpression(source: source, offset: token.start + 1),
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
    final Expression expression;
    switch (frame) {
      case _CascadeIndex():
        expression = CascadeIndexExpression(
          source: source,
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
            if (frame.element.isAwait && parts is! ForInParts) {
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
        if (frame case _Group(
          constKeyword: final Token keyword,
          fields: [Expression()],
          hasComma: false,
        )) {
          error(
            'expected_record_comma',
            'A record with one positional field needs a trailing comma.',
            keyword,
          );
        }
        switch (frame) {
          case _ArgumentList():
            frame.result = ArgumentList(
              source: source,
              start: frame.opening.start,
              end: end,
              arguments: frame.arguments,
            );
            frames.removeLast();
            if (matched) advance();
            return;
          case _Call():
            expression = InvocationExpression(
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
            );
          case _Construction():
            expression = InstanceCreationExpression(
              source: source,
              start: frame.keyword.start,
              end: end,
              kind: frame.keyword.kind == .keywordConst
                  ? .constKeyword
                  : .newKeyword,
              name: frame.components,
              typeArguments: frame.typeArguments,
              constructorName: frame.constructorName,
              arguments: ArgumentList(
                source: source,
                start: frame.opening.start,
                end: end,
                arguments: frame.arguments,
              ),
            );
          case _ConstShorthand():
            expression = ConstDotShorthandExpression(
              source: source,
              start: frame.keyword.start,
              end: end,
              name: frame.member,
              typeArguments: frame.typeArguments,
              arguments: ArgumentList(
                source: source,
                start: frame.opening.start,
                end: end,
                arguments: frame.arguments,
              ),
            );
          case _Group(
            fields: [final Expression value],
            hasComma: false,
            constKeyword: null,
          ):
            expression = ParenthesizedExpression(
              source: source,
              start: frame.opening.start,
              end: end,
              expression: value,
            );
          case _Group():
            expression = RecordExpression(
              source: source,
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
          when callee is! IdentifierExpression &&
              callee is! PropertyAccessExpression &&
              callee is! ThisExpression &&
              callee is! SuperExpression &&
              callee is! DotShorthandReferenceExpression:
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
