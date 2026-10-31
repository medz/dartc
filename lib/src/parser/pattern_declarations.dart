part of 'parser.dart';

extension on _Parser {
  bool get isPatternDeclaration {
    if (current.kind != .keywordVar && current.kind != .keywordFinal) {
      return false;
    }
    final child = _Parser.nested(this)..advance();
    final end = child.outerPatternEnd();
    return end != null &&
        (child.tokens[end].kind == .emptyBracketsAssign ||
            child.tokens[end + 1].kind == .assign ||
            child.tokens[end + 1].kind == .keywordIn);
  }

  int? outerPatternEnd() {
    var opening = cursor;
    if (current.kind == .less) {
      final end = lookahead.delimiters.afterTypeArguments(opening);
      if (end == null) return null;
      opening = end;
    } else if (current.kind.isIdentifier) {
      opening++;
      if (tokens[opening].kind == .dot) {
        opening++;
        if (!tokens[opening].kind.isTypeName) return null;
        opening++;
      }
      if (tokens[opening].kind == .less) {
        final end = lookahead.delimiters.afterTypeArguments(opening);
        if (end == null) return null;
        opening = end;
      }
      if (tokens[opening].kind == .question) opening++;
      if (tokens[opening].kind != .leftParen) return null;
    }
    if (tokens[opening].kind == .emptyBrackets ||
        tokens[opening].kind == .emptyBracketsAssign) {
      return opening;
    }
    if (tokens[opening].kind != .leftParen &&
        tokens[opening].kind != .leftBracket &&
        tokens[opening].kind != .leftBrace) {
      return null;
    }
    return lookahead.delimiters.closing(opening);
  }

  bool get startsPatternAssignment {
    final end = outerPatternEnd();
    return end != null &&
        (tokens[end].kind == .emptyBracketsAssign ||
            tokens[end + 1].kind == .assign);
  }

  bool parsePatternAssignment() {
    if (current.kind != .leftParen &&
        current.kind != .leftBracket &&
        current.kind != .leftBrace &&
        current.kind != .emptyBracketsAssign &&
        current.kind != .less &&
        !(current.kind.isIdentifier &&
            (tokens[cursor + 1].kind == .leftParen ||
                tokens[cursor + 1].kind == .dot ||
                tokens[cursor + 1].kind == .less))) {
      return false;
    }
    final end = outerPatternEnd();
    if (end == null ||
        tokens[end].kind != .emptyBracketsAssign &&
            tokens[end + 1].kind != .assign) {
      return false;
    }
    if (operators.length > operatorBase &&
        operators.last.kind.precedence != _assignmentPrecedence &&
        operators.last.kind != .question) {
      error(
        'invalid_pattern_assignment_position',
        'Parenthesize the pattern assignment in this operand.',
        current,
      );
    }
    final child = _Parser.nested(this);
    pendingSyntax = _OperandReader(
      this,
      child,
      _PatternAssignmentReader(child),
    );
    return true;
  }
}

final class _PatternAssignmentReader(final _Parser parser)
    extends _Reader<Expression> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final pattern = _PatternReader(parser, context: .assignment);
    yield pattern;
    parser.expect(.assign);
    final value = _ExpressionReader(parser);
    if (!value.start()) yield value;
    result = PatternAssignmentExpression(
      source: parser.source,
      start: pattern.result.start,
      end: value.result.end,
      pattern: pattern.result,
      value: value.result,
    );
  }
}

final class _PatternDeclarationReader(
  final _Parser parser, {
  final List<Annotation> metadata = const [],
}) extends _Reader<PatternVariableDeclaration> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    parser.advance();
    final pattern = _PatternReader(parser, context: .declaration);
    yield pattern;
    parser.expect(.assign);
    final value = _ExpressionReader(parser);
    if (!value.start()) yield value;
    result = PatternVariableDeclaration(
      source: parser.source,
      start: metadata.firstOrNull?.start ?? token.start,
      end: value.result.end,
      metadata: metadata,
      isFinal: token.kind == .keywordFinal,
      pattern: pattern.result,
      initializer: value.result,
    );
  }
}

final class _ForDeclarationReader(final _Parser parent, final _ForHeader frame)
    extends _Reader<void> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final child = _Parser.nested(parent);
    if (child.current.kind == .at) {
      final metadata = _MetadataReader(child);
      yield metadata;
      frame.metadata = metadata.result;
    }
    if (!child.isPatternDeclaration) {
      parent.adopt(child);
      yield* parent.readForVariables(frame);
      if (frame.declarations == null && frame.metadata.isNotEmpty) {
        parent.error(
          'expected_declaration',
          'Expected a variable declaration after metadata.',
          parent.current,
        );
      }
      return;
    }
    final token = child.current;
    child.advance();
    final pattern = _PatternReader(child, context: .declaration);
    yield pattern;
    final start = frame.metadata.firstOrNull?.start ?? token.start;
    if (child.current.kind == .keywordIn) {
      frame.target = PatternForInBinding(
        source: child.source,
        start: start,
        end: pattern.result.end,
        metadata: frame.metadata,
        isFinal: token.kind == .keywordFinal,
        pattern: pattern.result,
      );
      frame.phase = .iterable;
      child.advance();
    } else {
      child.expect(.assign);
      final value = _ExpressionReader(child);
      if (!value.start()) yield value;
      frame.initializer = PatternVariableDeclaration(
        source: child.source,
        start: start,
        end: value.result.end,
        metadata: frame.metadata,
        isFinal: token.kind == .keywordFinal,
        pattern: pattern.result,
        initializer: value.result,
      );
      frame.end = child.expect(.semicolon);
      frame.phase = .condition;
    }
    parent.adopt(child);
    parent.expectsOperand = true;
  }
}
