part of 'parser.dart';

extension on _Parser {
  bool tryTypeArguments() {
    final first = tokens[cursor + 1];
    if (!first.kind.isTypeName &&
        first.kind != .leftParen &&
        !(first.kind.isIdentifier && tokens[cursor + 2].kind == .dot)) {
      return false;
    }
    final start = cursor;
    final remainder = current;
    final cache = typeArguments ??= {};
    TypeArgumentList? arguments;
    if (cache.containsKey(start)) {
      final cached = cache[start];
      if (cached == null) return false;
      arguments = cached.$1;
      cursor = cached.$2;
      current = cached.$3;
    } else {
      arguments = _TypeReader(this).read(arguments: true) as TypeArgumentList?;
    }
    if (arguments == null || !current.kind.followsTypeArguments) {
      cursor = start;
      current = remainder;
      return false;
    }
    // A successful trial is the syntax tree; it is not parsed a second time.
    checkSelector();
    final target = values.removeLast();
    if (current.kind == .leftParen) {
      delimiters.add(
        _Call(
          current,
          values.length,
          operators.length,
          target,
          typeArguments: arguments,
        ),
      );
      advance();
      expectsOperand = true;
    } else {
      values.add(
        TypeInstantiationExpression(
          source: source,
          start: target.start,
          end: arguments.end,
          expression: target,
          typeArguments: arguments,
        ),
      );
    }
    return true;
  }

  void parseTypeOperator() {
    final token = current;
    while (operators.length > operatorBase) {
      final previous = operators.last;
      final precedence =
          prefixes.isNotEmpty && prefixes.last == operators.length - 1
          ? _prefixPrecedence
          : previous.kind.precedence;
      if (precedence < _relationalPrecedence) break;
      reduce();
    }
    final expression = values.removeLast();
    if (expression is CastExpression || expression is TypeTestExpression) {
      error(
        'chained_type_operator',
        'Parenthesize the type test or cast before another type operator.',
        token,
      );
    }
    advance();
    final negated = token.kind == .keywordIs && current.kind == .bang;
    if (negated) advance();
    final first = current;
    final reader = _TypeReader(this, afterIsOrAs: true);
    final type =
        reader.read() as TypeAnnotation? ??
        MissingTypeAnnotation(source: source, offset: first.start);
    if (reader.failure case final failure?) {
      error(failure.$1, failure.$2, failure.$3);
    }
    if (first.kind == .keywordVoid &&
        type is NamedTypeAnnotation &&
        type.prefix == null) {
      error('invalid_void_type', 'A type test or cast cannot use void.', first);
    }
    values.add(
      token.kind == .keywordAs
          ? CastExpression(
              source: source,
              start: expression.start,
              end: type.end,
              expression: expression,
              type: type,
            )
          : TypeTestExpression(
              source: source,
              start: expression.start,
              end: type.end,
              expression: expression,
              type: type,
              isNegated: negated,
            ),
    );
    checkTypeContinuation(current);
  }

  void checkTypeContinuation(Token token) {
    if (token.kind.precedence == _relationalPrecedence) {
      var operand = values.last;
      while (operand is CastExpression || operand is TypeTestExpression) {
        operand = switch (operand) {
          CastExpression(:final expression) => expression,
          TypeTestExpression(:final expression) => expression,
          _ => operand,
        };
      }
      if (operand is BinaryExpression &&
          (operand.op == .less ||
              operand.op == .lessEqual ||
              operand.op == .greater ||
              operand.op == .greaterEqual)) {
        error(
          'chained_comparison',
          'Parenthesize this comparison operand.',
          token,
        );
      }
    }
    if (token.kind.precedence > _relationalPrecedence ||
        token.kind == .dot ||
        token.kind == .nullAwareAccess ||
        token.kind == .leftParen ||
        token.kind == .leftBracket ||
        token.kind == .emptyBrackets ||
        token.kind == .question &&
            (tokens[cursor + 1].kind == .leftBracket ||
                tokens[cursor + 1].kind == .emptyBrackets) ||
        token.kind == .bang ||
        token.kind == .increment ||
        token.kind == .decrement) {
      error(
        'invalid_type_continuation',
        'Parenthesize the type test or cast before this operation.',
        token,
      );
    }
  }
}

extension on TokenKind {
  bool get followsTypeArguments => switch (this) {
    .leftParen ||
    .dot ||
    .equal ||
    .notEqual ||
    .rightParen ||
    .rightBracket ||
    .rightBrace ||
    .semicolon ||
    .colon ||
    .comma ||
    .eof => true,
    _ => false,
  };
}
