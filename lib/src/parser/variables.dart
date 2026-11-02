part of 'parser.dart';

final class _VariableDeclarations(
  final int start,
  final VariableKeyword keyword,
  final bool isLate,
  final int? type,
  int name,
) {
  int name = name;
  bool initializing = false;
  final List<int> variables = [];
}

final class _VariableReader(
  final _Parser parser, {
  final bool forLoop = false,
  final bool allowConditional = true,
}) extends _Reader<_VariableDeclarations?> {
  int? expressionStart;
  int? declarationEnd;

  @override
  Iterable<_Reader<Object?>> read() sync* {
    final initialCursor = parser.cursor;
    final first = parser.current;
    var isLate = false;
    int? type;
    // Modifier words can also name functions, followed by a call's arguments.
    if (parser.current.kind.isVariableModifier &&
        parser.tokens[parser.cursor + 1].kind == .leftParen) {
      parser.advance();
      final reader = _TypeReader(parser);
      if (!reader.start()) yield _TypeTask(reader);
      type = reader.result;
      if (type == null ||
          !parser.current.kind.isIdentifier ||
          !parser.tokens[parser.cursor + 1].kind.followsVariableName) {
        parser.cursor = initialCursor;
        parser.current = first;
        result = null;
        return;
      }
      isLate = first.kind == .keywordLate;
      if (forLoop || !isLate) {
        parser.error(
          forLoop ? 'invalid_for_modifier' : 'invalid_variable_modifier',
          'This modifier cannot be used on this variable.',
          first,
        );
      }
    }
    while (type == null &&
        parser.current.kind.isVariableModifier &&
        parser.tokens[parser.cursor + 1].kind != .keywordIn &&
        (parser.tokens[parser.cursor + 1].kind.isKeyword ||
            parser.tokens[parser.cursor + 1].kind.isIdentifier)) {
      if (isLate && parser.current.kind == .keywordLate) {
        parser.error(
          'duplicate_modifier',
          'Repeated late modifier.',
          parser.current,
        );
      }
      isLate = isLate || parser.current.kind == .keywordLate;
      if (forLoop || parser.current.kind != .keywordLate) {
        parser.error(
          forLoop ? 'invalid_for_modifier' : 'invalid_variable_modifier',
          'This modifier cannot be used on this variable.',
          parser.current,
        );
      }
      parser.advance();
    }
    final keyword = switch (parser.current.kind) {
      .keywordVar => VariableKeyword.varKeyword,
      .keywordFinal => VariableKeyword.finalKeyword,
      .keywordConst => VariableKeyword.constKeyword,
      _ => VariableKeyword.none,
    };
    if (keyword != .none) parser.advance();
    if (isLate && keyword == .constKeyword) {
      parser.error(
        'conflicting_modifiers',
        'A constant cannot be late.',
        first,
      );
    }

    if (type == null &&
        keyword != .varKeyword &&
        parser.canStartTypeBeforeName() &&
        possibleVariableType()) {
      final index = parser.cursor;
      final token = parser.current;
      final reader = _TypeReader(parser);
      if (!reader.start()) yield _TypeTask(reader);
      final parsed = reader.result;
      if (parsed != null &&
          parser.current.kind.isIdentifier &&
          parser.tokens[parser.cursor + 1].kind.followsVariableName) {
        type = parsed;
      } else {
        parser.cursor = index;
        parser.current = token;
      }
    }
    if (!forLoop &&
        !isLate &&
        keyword == .constKeyword &&
        type == null &&
        (!parser.current.kind.isIdentifier ||
            !parser.tokens[parser.cursor + 1].kind.followsVariableName)) {
      parser.cursor = initialCursor;
      parser.current = first;
      result = null;
      return;
    }
    if (type == null && keyword == .none && !isLate) {
      parser.cursor = initialCursor;
      parser.current = first;
      result = null;
      return;
    }
    if (isLate && type == null && keyword == .none) {
      parser.error(
        'expected_variable_type',
        'Expected a type, var, or final after late.',
        parser.current,
      );
    }
    if (allowConditional &&
        !forLoop &&
        !isLate &&
        keyword == .none &&
        (parser.arena.isKind(type, .namedTypeAnnotation) ||
            parser.arena.isKind(type, .recordTypeAnnotation)) &&
        parser.arena.start(type!) == first.start &&
        parser.current.kind.isIdentifier &&
        parser.tokens[parser.cursor + 1].kind == .assign &&
        parser.tokens[parser.cursor - 1].kind == .question &&
        parser.cursor < parser.lookahead.lastColon) {
      expressionStart = initialCursor;
      final question = parser.cursor - 1;
      result = _VariableDeclarations(
        first.start,
        keyword,
        isLate,
        type,
        parser.readVariableName(),
      );
      declarationEnd = parser.cursor;
      parser.cursor = question;
      parser.current = parser.tokens[question];
      final reader = _ConditionalReader(parser);
      yield reader;
      if (reader.result case final _ConditionalBranches branches) {
        parser.pendingBranches = (question, branches);
        parser.cursor = expressionStart!;
        result = null;
      } else {
        parser.cursor = declarationEnd!;
      }
      parser.current = parser.tokens[parser.cursor];
      return;
    }
    result = _VariableDeclarations(
      first.start,
      keyword,
      isLate,
      type,
      parser.readVariableName(),
    );
    return;
  }

  bool possibleVariableType() {
    final end = parser.possibleTypeEnd(parser.cursor);
    return end == null ||
        parser.tokens[end].kind.isIdentifier &&
            parser.tokens[end + 1].kind.followsVariableName;
  }
}

extension on _Parser {
  bool get canStartVariableDeclaration {
    if (current.kind == .keywordVar ||
        current.kind == .keywordFinal ||
        current.kind == .keywordConst ||
        current.kind.isVariableModifier) {
      return true;
    }
    if (!canStartTypeBeforeName()) return false;
    final end = possibleTypeEnd(cursor);
    return end == null ||
        tokens[end].kind.isIdentifier &&
            tokens[end + 1].kind.followsVariableName;
  }

  int readVariableName() {
    final token = current;
    if (!token.kind.isIdentifier) {
      error('expected_identifier', 'Expected a variable name.', token);
      return arena.identifier(start: token.start, end: token.start);
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

final class _VariablesReader(
  final _Parser parser,
  final _VariableDeclarations declarations, {
  final List<int> metadata = const [],
}) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() {
    final pending = _variables(null);
    return pending == null ? const [] : _resume(pending);
  }

  Iterable<_Reader<Object?>> _resume(_ExpressionReader reader) sync* {
    _ExpressionReader? pending = reader;
    while (pending != null) {
      yield pending;
      pending = _variables(pending.result);
    }
  }

  _ExpressionReader? _variables(int? initializer) {
    while (true) {
      if (initializer == null && parser.current.kind == .assign) {
        parser.advance();
        final reader = _ExpressionReader(parser);
        if (!reader.start()) return reader;
        initializer = reader.result;
      }
      declarations.variables.add(
        parser.arena.variableDeclaration(
          name: declarations.name,
          initializer: initializer,
        ),
      );
      if (parser.current.kind != .comma) break;
      initializer = null;
      parser.advance();
      declarations.name = parser.readVariableName();
    }
    result = parser.arena.variableDeclarationList(
      start: metadata.isEmpty
          ? declarations.start
          : parser.arena.start(metadata.first),
      metadata: metadata,
      end: parser.arena.end(declarations.variables.last),
      keyword: declarations.keyword,
      isLate: declarations.isLate,
      type: declarations.type,
      declarations: declarations.variables,
    );
    return null;
  }
}
