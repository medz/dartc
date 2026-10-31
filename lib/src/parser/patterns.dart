part of 'parser.dart';

/// The syntactic context of a pattern, before binding and type analysis.
enum PatternContext {
  /// A case pattern that can test values and declare variables.
  matching,

  /// A pattern inside a `var` or `final` declaration.
  declaration,

  /// A pattern assigning existing variables, without declaring new ones.
  assignment,
}

/// Parses one pattern through the end of [input].
///
/// [context] determines whether variable keywords and types are permitted.
/// Constant evaluation, bindings and exhaustiveness require analysis.
ParseResult<DartPattern> parsePattern(
  ScanResult input, {
  PatternContext context = .matching,
  LanguageVersion languageVersion = LanguageVersion.current,
}) {
  final parser = _Parser(input, languageVersion: languageVersion);
  final node = _PatternReader(parser, context: context).finish();
  while (parser.current.kind != .eof) {
    parser.unexpected();
  }
  return parser.finishResult(node);
}

final class _PatternReader(
  final _Parser parser, {
  final PatternContext context = .matching,
  final int precedence = 1,
}) extends _Reader<DartPattern> {
  Token get current => parser.current;
  SourceFile get source => parser.source;

  @override
  Iterable<_Reader<Object?>> read() sync* {
    yield* primary();
    var permitsUnary = result is! RelationalPattern;
    while (true) {
      final token = current;
      if (token.kind == .keywordAs ||
          token.kind == .question ||
          token.kind == .bang) {
        if (!permitsUnary) {
          parser.error(
            'invalid_unary_pattern',
            'Parenthesize this pattern before applying another suffix.',
            token,
          );
        }
        parser.advance();
        if (token.kind == .keywordAs) {
          final reader = _RequiredTypeReader(parser);
          yield reader;
          final type = reader.result;
          result = CastPattern(
            source: source,
            start: result.start,
            end: type.end,
            pattern: result,
            type: type,
          );
        } else if (token.kind == .question) {
          result = NullCheckPattern(
            source: source,
            start: result.start,
            end: token.end,
            pattern: result,
          );
        } else {
          result = NullAssertPattern(
            source: source,
            start: result.start,
            end: token.end,
            pattern: result,
          );
        }
        permitsUnary = false;
        continue;
      }
      final level = switch (token.kind) {
        .logicalOr => 1,
        .logicalAnd => 2,
        _ => 0,
      };
      if (level < precedence) return;
      parser.advance();
      final right = _PatternReader(
        parser,
        context: context,
        precedence: level + 1,
      );
      yield right;
      result = LogicalPattern(
        source: source,
        start: result.start,
        end: right.result.end,
        left: result,
        op: token.kind == .logicalAnd ? .and : .or,
        right: right.result,
      );
      permitsUnary = false;
    }
  }

  Iterable<_Reader<Object?>> primary() sync* {
    final token = current;
    if (token.kind == .eof ||
        token.kind == .rightParen ||
        token.kind == .rightBracket ||
        token.kind == .rightBrace ||
        token.kind == .comma ||
        token.kind == .colon ||
        token.kind == .arrow) {
      parser.error('expected_pattern', 'Expected a pattern.', token);
      result = MissingPattern(source: source, offset: token.start);
      return;
    }
    if (token.kind == .keywordVar || token.kind == .keywordFinal) {
      final keyword = token.kind == .keywordVar
          ? PatternVariableKeyword.varKeyword
          : PatternVariableKeyword.finalKeyword;
      parser.advance();
      yield* readVariableType();
      final type = variableType;
      if (type != null && keyword == .varKeyword) {
        parser.error(
          'type_after_var',
          "A 'var' pattern cannot also have a type.",
          token,
        );
      }
      variable(token, keyword, type);
      return;
    }
    var typedCollection = false;
    if (token.kind == .less) {
      final end = parser.lookahead.delimiters.afterTypeArguments(parser.cursor);
      typedCollection =
          end != null &&
          switch (parser.tokens[end].kind) {
            .leftBracket ||
            .emptyBrackets ||
            .emptyBracketsAssign ||
            .leftBrace => true,
            _ => false,
          };
    }
    if (typedCollection ||
        token.kind == .leftBracket ||
        token.kind == .emptyBrackets ||
        token.kind == .emptyBracketsAssign ||
        token.kind == .leftBrace) {
      final reader = _CollectionPatternReader(parser, context);
      yield reader;
      result = reader.result;
      return;
    }
    final relation = switch (token.kind) {
      .less => RelationalPatternOperator.less,
      .equal => RelationalPatternOperator.equal,
      .notEqual => RelationalPatternOperator.notEqual,
      .lessEqual => RelationalPatternOperator.lessEqual,
      .greater => RelationalPatternOperator.greater,
      .greaterEqual => RelationalPatternOperator.greaterEqual,
      _ => null,
    };
    if (relation != null) {
      parser.advance();
      final expression = _ExpressionReader(parser, boundary: .patternRelation);
      if (!expression.start()) yield expression;
      result = RelationalPattern(
        source: source,
        start: token.start,
        end: expression.result.end,
        op: relation,
        operand: expression.result,
      );
      return;
    }
    yield* readVariableType();
    final type = variableType;
    if (type != null) {
      variable(token, .none, type);
      return;
    }
    if (token.kind == .leftParen) {
      final fields = _PatternFieldsReader(parser, context);
      yield fields;
      final items = fields.result;
      result =
          items.length == 1 && items.single is DartPattern && !fields.hasComma
          ? ParenthesizedPattern(
              source: source,
              start: token.start,
              end: fields.end,
              pattern: items.single as DartPattern,
            )
          : RecordPattern(
              source: source,
              start: token.start,
              end: fields.end,
              fields: items,
            );
      return;
    }
    if (token.kind.isIdentifier) {
      final child = _Parser.nested(parser);
      final typeReader = _TypeReader(child);
      if (!typeReader.start()) yield _TypeTask(typeReader);
      final candidate = typeReader.result;
      if (candidate is NamedTypeAnnotation &&
          !candidate.isNullable &&
          child.current.kind == .leftParen &&
          typeReader.failure == null) {
        parser.adopt(child);
        final fields = _PatternFieldsReader(parser, context, object: true);
        yield fields;
        result = ObjectPattern(
          source: source,
          start: token.start,
          end: fields.end,
          type: candidate,
          fields: fields.result,
        );
        return;
      }
      if (parser.tokens[parser.cursor + 1].kind != .dot &&
          parser.tokens[parser.cursor + 1].kind != .leftBracket &&
          parser.tokens[parser.cursor + 1].kind != .emptyBrackets) {
        variable(token, .none, null);
        return;
      }
    }
    final hasConst = token.kind == .keywordConst;
    if (hasConst && parser.tokens[parser.cursor + 1].kind == .leftParen) {
      parser.advance();
    }
    final expression = _ExpressionReader(parser, boundary: .patternConstant);
    if (!expression.start()) yield expression;
    final value = expression.result;
    if (value case DotShorthandExpression(
      expression: ConstDotShorthandExpression(arguments: null),
    )) {
      parser.error(
        'invalid_const_prefix',
        'A const shorthand must invoke a constructor.',
        token,
      );
    }
    if (!hasConst && !validConstant(value)) {
      parser.error(
        'invalid_constant_pattern',
        'Use const (...) for a constant expression pattern.',
        token,
      );
    }
    result = ConstantPattern(
      source: source,
      start: token.start,
      end: value.end,
      hasConstKeyword: hasConst,
      expression: value,
    );
  }

  TypeAnnotation? variableType;

  Iterable<_Reader<Object?>> readVariableType() sync* {
    variableType = null;
    if (current.kind.isIdentifier &&
        parser.tokens[parser.cursor + 1].kind == .keywordWhen) {
      return;
    }
    if (!current.kind.isTypeName && current.kind != .leftParen) return;
    final end = parser.possibleTypeEnd(parser.cursor);
    if (end != null &&
        (!parser.tokens[end].kind.isIdentifier ||
            parser.tokens[end].kind == .keywordWhen ||
            parser.tokens[end].kind == .keywordAs)) {
      return;
    }
    final child = _Parser.nested(parser);
    final reader = _TypeReader(child);
    if (!reader.start()) yield _TypeTask(reader);
    final type = reader.result;
    if (type is! TypeAnnotation ||
        reader.failure != null ||
        !child.current.kind.isIdentifier ||
        child.current.kind == .keywordWhen ||
        child.current.kind == .keywordAs) {
      return;
    }
    parser.adopt(child);
    variableType = type;
  }

  void variable(
    Token first,
    PatternVariableKeyword keyword,
    TypeAnnotation? type,
  ) {
    if (context == .declaration && keyword != .none) {
      parser.error(
        'variable_keyword_in_pattern_declaration',
        'The enclosing declaration already supplies the variable keyword.',
        first,
      );
    }
    if (context == .assignment && (keyword != .none || type != null)) {
      parser.error(
        'variable_in_assignment_pattern',
        'An assignment pattern cannot declare variables.',
        first,
      );
    }
    final name = parser.readVariableName();
    if (name.text == 'when' || name.text == 'as') {
      parser.error(
        'invalid_pattern_identifier',
        'This identifier is reserved in patterns.',
        first,
      );
    }
    result = name.text == '_'
        ? WildcardPattern(
            source: source,
            start: first.start,
            end: name.end,
            keyword: keyword,
            type: type,
          )
        : keyword == .none && type == null
        ? IdentifierPattern(
            source: source,
            start: first.start,
            end: name.end,
            name: name,
          )
        : VariablePattern(
            source: source,
            start: first.start,
            end: name.end,
            keyword: keyword,
            type: type,
            name: name,
          );
  }

  bool validConstant(Expression value) => switch (value) {
    LiteralExpression() || StringExpression() || IdentifierExpression() => true,
    PropertyAccessExpression() ||
    IndexExpression() ||
    SwitchExpression() => true,
    UnaryExpression(
      op: .negate,
      operand: LiteralExpression(kind: .integer || .doubleLiteral),
    ) =>
      true,
    DotShorthandExpression() => true,
    _ => false,
  };
}

final class _CasePatternReader(
  final _Parser parser, {
  final bool condition = false,
  final bool constantExpression = false,
}) extends _Reader<CasePattern> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (condition && parser.current.kind == .keywordAwait) {
      parser.error(
        'await_in_case_condition',
        'Parenthesize an await-named constant in this case condition.',
        parser.current,
      );
    }
    DartPattern pattern;
    if (constantExpression) {
      final reader = _ExpressionReader(parser);
      if (!reader.start()) yield reader;
      final expression = reader.result;
      pattern = ConstantPattern(
        source: parser.source,
        start: expression.start,
        end: expression.end,
        expression: expression,
      );
    } else {
      final reader = _PatternReader(parser);
      yield reader;
      pattern = reader.result;
    }
    result = pattern;
    if (parser.current.kind == .keywordWhen) {
      parser.advance();
      final guard = _ExpressionReader(parser);
      if (!guard.start()) yield guard;
      result = GuardedPattern(
        source: parser.source,
        start: pattern.start,
        end: guard.result.end,
        pattern: pattern,
        guard: guard.result,
      );
    }
  }
}

final class _CollectionCaseReader(final _Parser parent, final _IfHeader frame)
    extends _Reader<void> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final child = _Parser.nested(parent);
    final pattern = _CasePatternReader(child, condition: true);
    yield pattern;
    frame.element.casePattern = pattern.result;
    child.expect(.rightParen);
    parent.adopt(child);
    parent.frames.removeLast();
    parent.expectsOperand = true;
  }
}
