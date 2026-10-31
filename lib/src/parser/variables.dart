part of 'parser.dart';

final class _VariableDeclarations(
  final int start,
  final VariableKeyword keyword,
  final bool isLate,
  final TypeAnnotation? type,
  Identifier name,
) {
  Identifier name = name;
  bool initializing = false;
  final List<VariableDeclaration> variables = [];
}

extension on _Parser {
  _VariableDeclarations? readVariableDeclarations({bool forLoop = false}) {
    final initialCursor = cursor;
    final first = current;
    var isLate = false;
    TypeAnnotation? type;
    // Modifier words can also name functions, followed by a call's arguments.
    if (current.kind.isVariableModifier &&
        tokens[cursor + 1].kind == .leftParen) {
      advance();
      type = _TypeReader(this).read() as TypeAnnotation?;
      if (type == null ||
          !current.kind.isIdentifier ||
          !tokens[cursor + 1].kind.followsVariableName) {
        cursor = initialCursor;
        current = first;
        return null;
      }
      isLate = first.kind == .keywordLate;
      if (forLoop || !isLate) {
        error(
          forLoop ? 'invalid_for_modifier' : 'invalid_variable_modifier',
          'This modifier cannot be used on this variable.',
          first,
        );
      }
    }
    while (type == null &&
        current.kind.isVariableModifier &&
        tokens[cursor + 1].kind != .keywordIn &&
        (tokens[cursor + 1].kind.isKeyword ||
            tokens[cursor + 1].kind.isIdentifier)) {
      if (isLate && current.kind == .keywordLate) {
        error('duplicate_modifier', 'Repeated late modifier.', current);
      }
      isLate = isLate || current.kind == .keywordLate;
      if (forLoop || current.kind != .keywordLate) {
        error(
          forLoop ? 'invalid_for_modifier' : 'invalid_variable_modifier',
          'This modifier cannot be used on this variable.',
          current,
        );
      }
      advance();
    }
    final keyword = switch (current.kind) {
      .keywordVar => VariableKeyword.varKeyword,
      .keywordFinal => VariableKeyword.finalKeyword,
      .keywordConst => VariableKeyword.constKeyword,
      _ => VariableKeyword.none,
    };
    if (keyword != .none) advance();
    if (isLate && keyword == .constKeyword) {
      error('conflicting_modifiers', 'A constant cannot be late.', first);
    }

    if (type == null && keyword != .varKeyword) {
      final index = cursor;
      final token = current;
      final parsed = _TypeReader(this).read() as TypeAnnotation?;
      if (parsed != null &&
          current.kind.isIdentifier &&
          tokens[cursor + 1].kind.followsVariableName) {
        type = parsed;
      } else {
        cursor = index;
        current = token;
      }
    }
    if (!forLoop &&
        !isLate &&
        keyword == .constKeyword &&
        type == null &&
        (!current.kind.isIdentifier ||
            !tokens[cursor + 1].kind.followsVariableName)) {
      cursor = initialCursor;
      current = first;
      return null;
    }
    if (type == null && keyword == .none && !isLate) {
      cursor = initialCursor;
      current = first;
      return null;
    }
    if (isLate && type == null && keyword == .none) {
      error(
        'expected_variable_type',
        'Expected a type, var, or final after late.',
        current,
      );
    }
    if (current.kind == .leftParen ||
        current.kind == .leftBracket ||
        current.kind == .leftBrace ||
        current.kind == .emptyBrackets) {
      error(
        'unsupported_syntax',
        'Pattern declarations are not yet supported.',
        current,
      );
    }
    if (!forLoop &&
        !isLate &&
        keyword == .none &&
        (type is NamedTypeAnnotation || type is RecordTypeAnnotation) &&
        type!.start == first.start &&
        current.kind.isIdentifier &&
        tokens[cursor + 1].kind == .assign &&
        tokens[cursor - 1].kind == .question &&
        cursor < lookahead.lastColon) {
      final declarationCursor = cursor;
      final name = current;
      cursor--;
      current = tokens[cursor];
      final result = lookahead.conditionals[cursor] ?? resolveConditional();
      if (result is _ConditionalBranches) {
        cursor = initialCursor;
        current = first;
        return null;
      }
      cursor = declarationCursor;
      current = name;
    }
    return _VariableDeclarations(
      first.start,
      keyword,
      isLate,
      type,
      readVariableName(),
    );
  }

  Identifier readVariableName() {
    final token = current;
    if (!token.kind.isIdentifier) {
      error('expected_identifier', 'Expected a variable name.', token);
      return Identifier(source: source, start: token.start, end: token.start);
    }
    advance();
    return identifier(token);
  }
}

extension on TokenKind {
  bool get isVariableModifier => switch (this) {
    .keywordAbstract ||
    .keywordCovariant ||
    .keywordExternal ||
    .keywordLate ||
    .keywordRequired ||
    .keywordStatic => true,
    _ => false,
  };
  bool get followsVariableName => switch (this) {
    .assign ||
    .comma ||
    .semicolon ||
    .keywordIn ||
    .rightParen ||
    .eof => true,
    _ => false,
  };
}
