part of 'parser.dart';

final class _ClosureReader(final _Parser parser, final int start)
    extends _Reader<FunctionExpression> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    TypeParameterList? typeParameters;
    if (parser.current.kind == .less) {
      final reader = _TypeReader(parser);
      if (!reader.start(parameters: true)) yield _TypeTask(reader);
      typeParameters = reader.result as TypeParameterList?;
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
    final parameters = _ParameterReader(parser, function: true);
    yield parameters;
    final body = _BodyReader(parser, declaration: false);
    yield body;
    result = FunctionExpression(
      source: parser.source,
      start: start,
      end: body.result.end,
      typeParameters: typeParameters,
      parameters: parameters.result,
      body: body.result,
    );
  }
}

final class _LocalFunctionReader(
  final _Parser parent,
  final _Parser parser,
  final int start,
) extends _Reader<LocalFunctionDeclaration?> {
  List<Annotation> metadata = const [];
  TypeAnnotation? returnType;
  Identifier? name;
  TypeParameterList? typeParameters;

  bool hasHead = false;

  Iterable<_Reader<Object?>> readHead() sync* {
    final headStart = parser.cursor;
    final headToken = parser.current;
    final untyped = parser.functionBodyAfterName();
    if (headToken.kind.isVariableModifier && !untyped) return;
    if (!untyped) {
      final end = parser.possibleTypeEnd(parser.cursor, beforeFunction: true);
      if (end != null) {
        if (!parser.tokens[end].kind.isIdentifier) return;
        var opening = end + 1;
        if (parser.tokens[opening].kind == .less) {
          opening =
              parser.lookahead.delimiters.afterTypeArguments(opening) ??
              opening;
        }
        if (!parser.functionBodyFollows(opening)) return;
      }
    }
    TypeAnnotation? parsed;
    if (!untyped && parser.canStartTypeBeforeName) {
      final reader = _TypeReader(parser, beforeFunction: true);
      if (!reader.start()) yield _TypeTask(reader);
      parsed = reader.result as TypeAnnotation?;
    }
    if (parsed != null && parser.current.kind.isIdentifier) {
      returnType = parsed;
    } else {
      parser.cursor = headStart;
      parser.current = headToken;
    }
    if (!parser.current.kind.isIdentifier) return;
    name = parser.identifier(parser.current);
    parser.advance();
    if (parser.current.kind == .less) {
      final reader = _TypeReader(parser);
      if (!reader.start(parameters: true)) yield _TypeTask(reader);
      typeParameters = reader.result as TypeParameterList?;
      if (typeParameters == null) return;
    }
    hasHead = parser.functionBodyFollows(parser.cursor);
  }

  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (name == null) {
      final annotations = _MetadataReader(parser);
      yield annotations;
      metadata = annotations.result;
      yield* readHead();
      if (!hasHead) {
        result = null;
        return;
      }
    }
    final parameters = _ParameterReader(
      parser,
      function: true,
      allowCovariant: false,
    );
    yield parameters;
    final body = _BodyReader(parser);
    yield body;
    result = LocalFunctionDeclaration(
      source: parser.source,
      start: start,
      end: body.result.end,
      metadata: metadata,
      returnType: returnType,
      name: name!,
      typeParameters: typeParameters,
      parameters: parameters.result,
      body: body.result,
    );
    parent.adopt(parser);
  }
}

extension on _Parser {
  bool functionBodyAfterName({bool allowEmpty = false, int? nameIndex}) {
    final index = nameIndex ?? cursor;
    final kind = tokens[index].kind;
    if (!kind.isIdentifier) return false;
    var opening = index + 1;
    if (tokens[index + 1].kind != .less) {
      if (!functionBodyFollows(opening, allowEmpty: allowEmpty)) return false;
    } else {
      final end = lookahead.delimiters.afterTypeArguments(opening);
      if (end == null || !functionBodyFollows(end, allowEmpty: allowEmpty)) {
        return false;
      }
      opening = end;
    }
    if (kind == .keywordFunction || kind.isVariableModifier) {
      final following = tokens[lookahead.delimiters.closing(opening)! + 1].kind;
      return following == .arrow ||
          following == .leftBrace ||
          allowEmpty && following == .semicolon;
    }
    return true;
  }

  bool functionBodyFollows(int opening, {bool allowEmpty = false}) {
    if (tokens[opening].kind != .leftParen) return false;
    final end = lookahead.delimiters.closing(opening);
    if (end == null) return false;
    return switch (tokens[end + 1].kind) {
      .arrow || .leftBrace || .keywordAsync || .keywordSync => true,
      .semicolon => allowEmpty,
      _ => false,
    };
  }

  bool parseFunctionExpression() {
    if (current.kind == .leftParen && !functionBodyFollows(cursor)) {
      return false;
    }
    final start = current.start;
    final child = _Parser.nested(this);
    if (child.current.kind == .less) {
      final end = lookahead.delimiters.afterTypeArguments(cursor);
      if (end == null || !functionBodyFollows(end)) return false;
    }
    pendingSyntax = _OperandReader(this, child, _ClosureReader(child, start));
    return true;
  }

  _LocalFunctionReader? localFunction() {
    if (!(current.kind.isTypeName ||
        current.kind.isIdentifier ||
        current.kind == .leftParen ||
        current.kind == .at)) {
      return null;
    }
    if (current.kind.isIdentifier &&
        current.kind != .keywordFunction &&
        tokens[cursor + 1].kind == .leftParen &&
        !functionBodyFollows(cursor + 1)) {
      return null;
    }
    if (current.kind != .at &&
        !canStartTypeBeforeName &&
        tokens[cursor + 1].kind != .leftParen &&
        tokens[cursor + 1].kind != .less) {
      return null;
    }
    final child = _Parser.nested(this);
    final reader = _LocalFunctionReader(this, child, current.start);
    return reader;
  }
}
