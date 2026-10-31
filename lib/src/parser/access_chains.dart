part of 'parser.dart';

final class _Cascade(
  super.valueBase,
  super.operatorBase,
  final Expression target,
  final bool isNullAware,
) extends _Frame {
  final List<Expression> sections = [];
  bool assigned = false;
}

final class _CascadeIndex(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Token marker,
) extends _Delimiter {
  @override
  TokenKind get closing => .rightBracket;
}

final class _Shorthand(super.valueBase, super.operatorBase, final bool isConst)
    extends _Frame {
  NullAssertionExpression? pendingBang;
}

final class _ConstShorthand(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final Token keyword,
  final Identifier member,
  final TypeArgumentList? typeArguments,
) extends _Arguments;

extension on _Parser {
  void openCascade() {
    // Assignments in conditional branches belong to the receiver. An outer
    // assignment instead receives the result of the complete cascade.
    var firstConditional = operators.length;
    for (var i = operatorBase; i < operators.length; i++) {
      if (operators[i].kind == .question) {
        firstConditional = i;
        break;
      }
    }
    while (operators.length > operatorBase) {
      if (operators.last.kind.precedence == _assignmentPrecedence &&
          operators.length - 1 < firstConditional) {
        break;
      }
      reduce();
    }
    final target = values.removeLast();
    checkValue(target);
    frames.add(
      _Cascade(
        values.length,
        operators.length,
        target,
        current.kind == .nullAwareCascade,
      ),
    );
    openCascadeSection();
  }

  void openCascadeSection() {
    final marker = current;
    advance();
    final token = current;
    if (token.kind == .leftBracket) {
      frames.add(_CascadeIndex(token, values.length, operators.length, marker));
      advance();
      expectsOperand = true;
      return;
    }
    if (token.kind == .emptyBrackets || token.kind == .emptyBracketsAssign) {
      error('expected_expression', 'Expected an index expression.', token);
      values.add(
        CascadeIndexExpression(
          source: source,
          start: marker.start,
          end: token.start + 2,
          index: MissingExpression(source: source, offset: token.start + 1),
        ),
      );
      consumeEmptyBrackets();
    } else {
      final valid = token.kind.isIdentifier || token.kind == .keywordNew;
      if (valid) {
        advance();
      } else {
        error('expected_identifier', 'Expected a cascade member name.', token);
      }
      values.add(
        CascadePropertyExpression(
          source: source,
          start: marker.start,
          end: valid ? token.end : token.start,
          property: valid
              ? identifier(token)
              : Identifier(
                  source: source,
                  start: token.start,
                  end: token.start,
                ),
        ),
      );
    }
    expectsOperand = false;
  }

  bool endCascadeAtBoundary(_Cascade frame) {
    final kind = current.kind;
    if (kind == .cascade || kind == .nullAwareCascade) {
      frame.sections.add(finishExpression(frame.valueBase, frame.operatorBase));
      if (kind == .nullAwareCascade) {
        error(
          'null_aware_cascade_order',
          "Only the first cascade section can use '?..'.",
          current,
        );
      }
      frame.assigned = false;
      openCascadeSection();
      return true;
    }
    if (frame.assigned) {
      if (kind != .eof &&
          !kind.endsExpression &&
          !(kind == .colon &&
              (questions.isEmpty || questions.last < frame.operatorBase))) {
        return false;
      }
    } else if (kind.isAccessSelector ||
        kind == .question && tokens[cursor + 1].kind == .leftBracket ||
        kind.precedence == _assignmentPrecedence) {
      return false;
    }
    closeCascade(frame);
    return true;
  }

  void closeCascade(_Cascade frame) {
    frame.sections.add(finishExpression(frame.valueBase, frame.operatorBase));
    frames.removeLast();
    values.add(
      CascadeExpression(
        source: source,
        start: frame.target.start,
        end: frame.sections.last.end,
        target: frame.target,
        isNullAware: frame.isNullAware,
        sections: frame.sections,
      ),
    );
    expectsOperand = false;
  }

  void openShorthand() {
    final keyword = current.kind == .keywordConst ? current : null;
    if (keyword != null) advance();
    final dot = current;
    advance();
    final token = current;
    final valid = token.kind.isIdentifier || token.kind == .keywordNew;
    final name = valid
        ? identifier(token)
        : Identifier(source: source, start: token.start, end: token.start);
    if (valid) {
      advance();
    } else {
      error('expected_identifier', 'Expected a shorthand member name.', token);
    }
    frames.add(_Shorthand(values.length, operators.length, keyword != null));
    if (keyword == null) {
      values.add(
        DotShorthandReferenceExpression(
          source: source,
          start: dot.start,
          end: name.end,
          name: name,
        ),
      );
      expectsOperand = false;
      return;
    }
    TypeArgumentList? types;
    if (current.kind == .less) {
      final start = cursor;
      final remainder = current;
      types = _TypeReader(this).read(arguments: true) as TypeArgumentList?;
      if (types == null || !current.kind.followsTypeArguments) {
        cursor = start;
        current = remainder;
        types = null;
      }
    }
    if (current.kind == .leftParen) {
      frames.add(
        _ConstShorthand(
          current,
          values.length,
          operators.length,
          keyword,
          name,
          types,
        ),
      );
      advance();
      expectsOperand = true;
    } else {
      values.add(
        ConstDotShorthandExpression(
          source: source,
          start: keyword.start,
          end: types?.end ?? name.end,
          name: name,
          typeArguments: types,
        ),
      );
      expectsOperand = false;
    }
  }

  bool endShorthandAtBoundary(_Shorthand frame) {
    final kind = current.kind;
    if (frame.pendingBang != null) {
      if (kind == .dot ||
          kind == .nullAwareAccess ||
          kind == .leftParen ||
          kind == .leftBracket ||
          kind == .emptyBrackets ||
          kind == .emptyBracketsAssign ||
          kind == .question) {
        frame.pendingBang = null;
      } else if (kind != .less) {
        closeShorthand(frame);
        return true;
      }
    }
    if (kind.isAccessSelector ||
        kind == .question && tokens[cursor + 1].kind == .leftBracket) {
      return false;
    }
    closeShorthand(frame);
    return true;
  }

  void closeShorthand(_Shorthand frame) {
    final value = finishExpression(frame.valueBase, frame.operatorBase);
    final bang = frame.isConst ? frame.pendingBang : null;
    final expression = bang?.operand ?? value;
    final shorthand = DotShorthandExpression(
      source: source,
      start: expression.start,
      end: expression.end,
      expression: expression,
    );
    frames.removeLast();
    values.add(
      bang == null
          ? shorthand
          : NullAssertionExpression(
              source: source,
              start: shorthand.start,
              end: bang.end,
              operand: shorthand,
            ),
    );
    if (value == selectorTarget) selectorTarget = values.last;
    if (value == postfixTarget) postfixTarget = values.last;
    expectsOperand = false;
  }

  void prepareConditional() {
    if (frames.lastOrNull case final _Shorthand frame) {
      closeShorthand(frame);
    } else if (frames.lastOrNull case final _Cascade frame
        when !frame.assigned) {
      closeCascade(frame);
      error(
        'invalid_cascade_continuation',
        'Parenthesize the cascade before this operation.',
        current,
      );
    }
  }
}

extension on TokenKind {
  bool get followsSelectorBang => switch (this) {
    .dot ||
    .nullAwareAccess ||
    .leftParen ||
    .leftBracket ||
    .emptyBrackets ||
    .emptyBracketsAssign ||
    .question => true,
    _ => false,
  };

  bool get isAccessSelector => switch (this) {
    .dot ||
    .nullAwareAccess ||
    .leftParen ||
    .leftBracket ||
    .emptyBrackets ||
    .emptyBracketsAssign ||
    .bang ||
    .less => true,
    _ => false,
  };
}
