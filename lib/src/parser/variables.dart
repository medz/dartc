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

final class _VariableReader(
  final _Parser parser, {
  final bool forLoop = false,
  final bool allowConditional = true,
}) extends _Reader<_VariableDeclarations?> {
  int? expressionStart;
  int? declarationEnd;

  bool start() {
    final initialCursor = parser.cursor;
    final first = parser.current;
    var isLate = false;
    TypeAnnotation? type;
    // Modifier words can also name functions, followed by a call's arguments.
    if (parser.current.kind.isVariableModifier &&
        parser.tokens[parser.cursor + 1].kind == .leftParen) {
      parser.advance();
      type = _TypeReader(parser).read() as TypeAnnotation?;
      if (type == null ||
          !parser.current.kind.isIdentifier ||
          !parser.tokens[parser.cursor + 1].kind.followsVariableName) {
        parser.cursor = initialCursor;
        parser.current = first;
        result = null;
        return true;
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

    if (type == null && keyword != .varKeyword) {
      final index = parser.cursor;
      final token = parser.current;
      final parsed = _TypeReader(parser).read() as TypeAnnotation?;
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
      return true;
    }
    if (type == null && keyword == .none && !isLate) {
      parser.cursor = initialCursor;
      parser.current = first;
      result = null;
      return true;
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
        (type is NamedTypeAnnotation || type is RecordTypeAnnotation) &&
        type!.start == first.start &&
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
      final branches = parser.lookahead.conditionals[question];
      if (branches == null) return false;
      select(branches);
      return true;
    }
    result = _VariableDeclarations(
      first.start,
      keyword,
      isLate,
      type,
      parser.readVariableName(),
    );
    return true;
  }

  @override
  Iterable<_Reader<Object?>> read() sync* {
    final reader = _ConditionalReader(parser);
    yield reader;
    select(reader.result);
  }

  void select(_ConditionalResult branches) {
    if (branches is _ConditionalBranches) {
      parser.cursor = expressionStart!;
      result = null;
    } else {
      parser.cursor = declarationEnd!;
    }
    parser.current = parser.tokens[parser.cursor];
  }
}

extension on _Parser {
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

final class _VariablesReader(
  final _Parser parser,
  final _VariableDeclarations declarations, {
  final List<Annotation> metadata = const [],
}) extends _Reader<VariableDeclarationList> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    while (true) {
      Expression? initializer;
      if (parser.current.kind == .assign) {
        parser.advance();
        final reader = _ExpressionReader(parser);
        if (!reader.start()) yield reader;
        initializer = reader.result;
      }
      declarations.variables.add(
        VariableDeclaration(
          source: parser.source,
          start: declarations.name.start,
          end: initializer?.end ?? declarations.name.end,
          name: declarations.name,
          initializer: initializer,
        ),
      );
      if (parser.current.kind != .comma) break;
      parser.advance();
      declarations.name = parser.readVariableName();
    }
    result = VariableDeclarationList(
      source: parser.source,
      start: metadata.isEmpty ? declarations.start : metadata.first.start,
      metadata: metadata,
      end: declarations.variables.last.end,
      keyword: declarations.keyword,
      isLate: declarations.isLate,
      type: declarations.type,
      declarations: declarations.variables,
    );
  }
}
