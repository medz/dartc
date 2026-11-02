part of 'parser.dart';

extension on _Parser {
  Iterable<_Reader<Object?>> readConstruction() sync* {
    final keyword = current;
    advance();
    int readName({bool continuation = false}) {
      final token = current;
      if (token.kind.isIdentifier ||
          continuation && token.kind == .keywordNew) {
        advance();
        return identifier(token);
      }
      error(
        'expected_identifier',
        'Expected a constructor or type name.',
        token,
      );
      if (token.kind.isKeyword) {
        advance();
        return identifier(token);
      }
      return arena.putIdentifier(
        source: source,
        start: token.start,
        end: token.start,
      );
    }

    final components = [readName()];
    if (current.kind == .dot) {
      advance();
      components.add(readName(continuation: true));
    }
    int? types;
    if (current.kind == .less) {
      final reader = _TypeReader(this);
      if (!reader.start(arguments: true)) yield _TypeTask(reader);
      types = arena.asTypeArgumentListOrNull(reader.result);
      if (reader.failure case final failure?) {
        error(failure.$1, failure.$2, failure.$3);
      }
    }
    int? constructorName;
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
        arena.putInstanceCreationExpression(
          source: source,
          start: keyword.start,
          end: current.start,
          kind: keyword.kind == .keywordConst ? .constKeyword : .newKeyword,
          name: components,
          typeArguments: types,
          constructorName: constructorName,
          arguments: arena.putArgumentList(
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
    frames.add(
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
    var target = values.last;
    var assertions = 0;
    while (true) {
      if (arena.isNullAssertionExpression(target)) {
        assertions++;
        target = arena.rNullAssertionExpressionOperand(target);
      } else if (arena.isDotShorthandExpression(target)) {
        target = arena.rDotShorthandExpressionExpression(target);
      } else {
        break;
      }
    }
    final frame = frames.lastOrNull;
    final afterPrefix =
        (arena.isConstDotShorthandExpression(target) || assertions > 1) &&
        !(frame is _Cascade && !frame.assigned);
    if (afterPrefix &&
        !(operators.length > operatorBase &&
            prefixes.isNotEmpty &&
            prefixes.last == operators.length - 1)) {
      return false;
    }
    final first = tokens[cursor + 1];
    if (!first.kind.isTypeName &&
        first.kind != .leftParen &&
        !(first.kind.isIdentifier && tokens[cursor + 2].kind == .dot)) {
      return false;
    }
    final end = lookahead.afterTypeArguments(cursor);
    if (end == null || !tokens[end].kind.followsTypeArguments) return false;
    final start = cursor;
    final remainder = current;
    final reader = _TypeReader(this);
    if (!reader.start(arguments: true)) {
      pendingSyntax = _SyntaxTask(
        readTypeArgumentSuffix(reader, start, remainder, afterPrefix),
      );
      return true;
    }
    return acceptTypeArguments(
      arena.asTypeArgumentListOrNull(reader.result),
      start,
      remainder,
      afterPrefix,
    );
  }

  Iterable<_Reader<Object?>> readTypeArgumentSuffix(
    _TypeReader reader,
    int start,
    Token remainder,
    bool afterPrefix,
  ) sync* {
    yield _TypeTask(reader);
    if (!acceptTypeArguments(
      arena.asTypeArgumentListOrNull(reader.result),
      start,
      remainder,
      afterPrefix,
    )) {
      parseContinuation(skipTypeArguments: true);
    }
  }

  bool acceptTypeArguments(
    int? arguments,
    int start,
    Token remainder,
    bool afterPrefix,
  ) {
    if (arguments == null || !current.kind.followsTypeArguments) {
      cursor = start;
      current = remainder;
      return false;
    }
    // A successful trial is the syntax tree; it is not parsed a second time.
    if (afterPrefix) reduce();
    checkSelector();
    if (frames.lastOrNull case final _Shorthand frame) {
      frame.pendingBang = null;
    }
    final target = values.removeLast();
    if (current.kind == .leftParen) {
      frames.add(
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
        arena.putTypeInstantiationExpression(
          source: source,
          start: arena.rStart(target),
          end: arena.rEnd(arguments),
          expression: target,
          typeArguments: arguments,
        ),
      );
      if (target == selectorTarget) selectorTarget = values.last;
    }
    return true;
  }

  Iterable<_Reader<Object?>> readTypeOperator() sync* {
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
    if (arena.isCastExpression(expression) ||
        arena.isTypeTestExpression(expression)) {
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
    if (!reader.start()) yield _TypeTask(reader);
    final type =
        arena.asTypeAnnotationOrNull(reader.result) ??
        arena.putMissingTypeAnnotation(source: source, offset: first.start);
    if (reader.failure case final failure?) {
      error(failure.$1, failure.$2, failure.$3);
    }
    if (first.kind == .keywordVoid &&
        arena.isNamedTypeAnnotation(type) &&
        arena.rNamedTypeAnnotationPrefix(type) == null) {
      error('invalid_void_type', 'A type test or cast cannot use void.', first);
    }
    values.add(
      token.kind == .keywordAs
          ? arena.putCastExpression(
              source: source,
              start: arena.rStart(expression),
              end: arena.rEnd(type),
              expression: expression,
              type: type,
            )
          : arena.putTypeTestExpression(
              source: source,
              start: arena.rStart(expression),
              end: arena.rEnd(type),
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
      while (arena.isCastExpression(operand) ||
          arena.isTypeTestExpression(operand)) {
        operand = switch ((arena.maybe(operand) as Expression)) {
          CastExpression(refExpression: final expression) => expression,
          TypeTestExpression(refExpression: final expression) => expression,
          _ => operand,
        };
      }
      if (arena.isBinaryExpression(operand) &&
          (arena.rBinaryExpressionOp(operand) == .less ||
              arena.rBinaryExpressionOp(operand) == .lessEqual ||
              arena.rBinaryExpressionOp(operand) == .greater ||
              arena.rBinaryExpressionOp(operand) == .greaterEqual)) {
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
