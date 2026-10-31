part of 'parser.dart';

final class _ClosureReader(
  final _Parser parser,
  final int start,
  final TypeParameterList? typeParameters,
) extends _Reader<FunctionExpression> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
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

  bool readHead() {
    final headStart = parser.cursor;
    final headToken = parser.current;
    final untyped = parser.functionBodyAfterName();
    if (headToken.kind.isVariableModifier && !untyped) return false;
    final parsed = untyped || !parser.canStartTypeBeforeName
        ? null
        : _TypeReader(parser, beforeFunction: true).read() as TypeAnnotation?;
    if (parsed != null && parser.current.kind.isIdentifier) {
      returnType = parsed;
    } else {
      parser.cursor = headStart;
      parser.current = headToken;
    }
    if (!parser.current.kind.isIdentifier) return false;
    name = parser.identifier(parser.current);
    parser.advance();
    if (parser.current.kind == .less) {
      typeParameters =
          _TypeReader(parser).read(parameters: true) as TypeParameterList?;
      if (typeParameters == null) return false;
    }
    return parser.functionBodyFollows(parser.cursor);
  }

  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (name == null) {
      final annotations = _MetadataReader(parser);
      yield annotations;
      metadata = annotations.result;
      if (!readHead()) {
        result = null;
        return;
      }
    }
    final parameters = _ParameterReader(parser, function: true);
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
  bool functionBodyAfterName({bool allowEmpty = false}) {
    if (!current.kind.isIdentifier) return false;
    var opening = cursor + 1;
    if (tokens[cursor + 1].kind != .less) {
      if (!functionBodyFollows(opening, allowEmpty: allowEmpty)) return false;
    } else {
      final child = _Parser.nested(this)..advance();
      if (_TypeReader(child).read(parameters: true) == null ||
          !child.functionBodyFollows(child.cursor, allowEmpty: allowEmpty)) {
        return false;
      }
      opening = child.cursor;
    }
    if (current.kind == .keywordFunction || current.kind.isVariableModifier) {
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
    TypeParameterList? typeParameters;
    if (child.current.kind == .less) {
      typeParameters =
          _TypeReader(child).read(parameters: true) as TypeParameterList?;
      if (typeParameters == null || !child.functionBodyFollows(child.cursor)) {
        return false;
      }
    }
    pendingSyntax = _OperandReader(
      this,
      child,
      _ClosureReader(child, start, typeParameters),
    );
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
    if (current.kind != .at && !reader.readHead()) return null;
    return reader;
  }
}
