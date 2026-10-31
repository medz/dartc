part of 'parser.dart';

extension on _Parser {
  void parseConstruction() {
    final keyword = current;
    advance();
    Identifier readName({bool continuation = false}) {
      final token = current;
      if (token.kind.isIdentifier ||
          continuation && token.kind == .keywordNew) {
        advance();
        return identifier(token);
      }
      error(
        token.kind == .dot ? 'unsupported_syntax' : 'expected_identifier',
        token.kind == .dot
            ? 'Dot shorthand parsing is not yet supported.'
            : 'Expected a constructor or type name.',
        token,
      );
      if (token.kind.isKeyword) {
        advance();
        return identifier(token);
      }
      return Identifier(source: source, start: token.start, end: token.start);
    }

    final components = [readName()];
    if (current.kind == .dot) {
      advance();
      components.add(readName(continuation: true));
    }
    TypeArgumentList? types;
    if (current.kind == .less) {
      final reader = _TypeReader(this);
      types = reader.read(arguments: true) as TypeArgumentList?;
      if (reader.failure case final failure?) {
        error(failure.$1, failure.$2, failure.$3);
      }
    }
    Identifier? constructorName;
    if (current.kind == .dot) {
      advance();
      final name = readName(continuation: true);
      if (types == null) {
        components.add(name);
      } else {
        constructorName = name;
      }
    }
    if (current.kind != .leftParen) {
      error('expected_arguments', 'Expected constructor arguments.', current);
      values.add(
        InstanceCreationExpression(
          source: source,
          start: keyword.start,
          end: current.start,
          kind: keyword.kind == .keywordConst ? .constKeyword : .newKeyword,
          name: components,
          typeArguments: types,
          constructorName: constructorName,
          arguments: ArgumentList(
            source: source,
            start: current.start,
            end: current.start,
            arguments: const [],
          ),
        ),
      );
      expectsOperand = false;
      return;
    }
    delimiters.add(
      _Construction(
        current,
        values.length,
        operators.length,
        keyword,
        components,
        types,
        constructorName,
      ),
    );
    advance();
    expectsOperand = true;
  }

  bool tryTypeArguments() {
    final first = tokens[cursor + 1];
    if (!first.kind.isTypeName &&
        first.kind != .leftParen &&
        !(first.kind.isIdentifier && tokens[cursor + 2].kind == .dot)) {
      return false;
    }
    if (cursor >= lookahead.lastTypeArgumentCloser) return false;
    final start = cursor;
    final remainder = current;
    final cache = lookahead.typeArguments;
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
          checkedNullAware: target == selectorTarget && checkedNullAware,
        ),
      );
      advance();
      expectsOperand = true;
    } else {
      checkValue(target);
      values.add(
        TypeInstantiationExpression(
          source: source,
          start: target.start,
          end: arguments.end,
          expression: target,
          typeArguments: arguments,
        ),
      );
      if (target == selectorTarget) selectorTarget = values.last;
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
    checkValue(expression);
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
    .interpolationEnd ||
    .semicolon ||
    .colon ||
    .comma ||
    .eof => true,
    _ => false,
  };
}
