part of 'parser.dart';

extension on _Parser {
  bool get hasParametersAfterName {
    final next = tokens[cursor + 1].kind;
    if (next == .leftParen) return true;
    if (next != .less) return false;
    final end = lookahead.delimiters.afterTypeArguments(cursor + 1);
    return end != null && tokens[end].kind == .leftParen;
  }
}

final class _DeclarationName(final _Parser parser) {
  TypeAnnotation? type;
  late Identifier name;
  TokenKind? accessor;
  TypeParameterList? typeParameters;
  DeclaredOperator? op;

  Iterable<_Reader<Object?>> read({
    bool alias = false,
    bool member = false,
  }) sync* {
    final initial = parser.cursor;
    final first = parser.current;
    if (!(first.kind == .keywordGet || first.kind == .keywordSet) &&
        parser.canStartTypeBeforeName) {
      final reader = _TypeReader(parser, beforeFunction: true);
      if (!reader.start()) yield _TypeTask(reader);
      final parsed = reader.result as TypeAnnotation?;
      if (parsed != null && parser.current.kind.isIdentifier) {
        type = parsed;
      } else {
        parser.cursor = initial;
        parser.current = first;
      }
    }
    if (member &&
        parser.current.kind == .keywordOperator &&
        parser.tokens[parser.cursor + 1].kind != .leftParen &&
        (parser.tokens[parser.cursor + 1].kind != .less ||
            parser.tokens[parser.cursor + 2].kind == .leftParen)) {
      accessor = .keywordOperator;
      parser.advance();
      final token = parser.current;
      var spelling = token.lexeme;
      if (token.kind == .leftBracket) {
        parser.advance();
        parser.expect(.rightBracket);
        spelling = '[]';
        if (parser.current.kind == .assign) {
          spelling = '[]=';
          parser.advance();
        }
      } else {
        parser.advance();
      }
      for (final candidate in DeclaredOperator.values) {
        if (candidate.spelling == spelling) op = candidate;
      }
      if (op == null) {
        parser.error(
          'invalid_operator',
          'Expected a declarable operator.',
          token,
        );
      }
      return;
    }
    if (!alias &&
        (parser.current.kind == .keywordGet ||
            parser.current.kind == .keywordSet) &&
        parser.tokens[parser.cursor + 1].kind.isIdentifier) {
      accessor = parser.current.kind;
      parser.advance();
    }
    name = parser.readVariableName();
    if (parser.current.kind == .less) {
      final reader = _TypeReader(parser);
      if (!reader.start(parameters: true)) yield _TypeTask(reader);
      typeParameters = reader.result as TypeParameterList?;
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
  }
}

final class _TopLevelReader(
  final _Parser parser,
  final int start,
  final List<Annotation> metadata,
) extends _Reader<TopLevelDeclaration> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (parser.startsTypeDeclaration) {
      final reader = _TypeDeclarationReader(parser, start, metadata);
      yield reader;
      result = reader.result;
      return;
    }
    if (parser.current.kind == .keywordTypedef &&
        !parser.hasParametersAfterName) {
      yield* alias();
      return;
    }
    final external =
        parser.current.kind == .keywordExternal &&
        !parser.hasParametersAfterName;
    if (external) parser.advance();
    _VariableDeclarations? variables;
    if (parser.canStartVariableDeclaration) {
      final reader = _VariableReader(parser, allowConditional: false);
      yield reader;
      variables = reader.result;
    }
    if (variables case final declarations?) {
      final reader = _VariablesReader(parser, declarations, metadata: metadata);
      yield reader;
      result = TopLevelVariableDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        isExternal: external,
        variables: reader.result,
      );
      return;
    }
    final initial = parser.cursor;
    final header = _DeclarationName(parser);
    yield* header.read();
    if (header.name.start == header.name.end) {
      parser.error(
        'expected_declaration',
        'Expected a top-level declaration.',
        parser.current,
      );
      if (parser.cursor == initial && parser.current.kind != .eof) {
        parser.advance();
      }
      result = MissingTopLevelDeclaration(source: parser.source, offset: start);
      return;
    }
    FormalParameterList? parameters;
    if (header.accessor != .keywordGet) {
      final reader = _ParameterReader(
        parser,
        function: true,
        allowCovariant: false,
      );
      yield reader;
      parameters = reader.result;
      if (header.accessor == .keywordSet) {
        parser.checkSetterParameters(parameters);
      }
    }
    final body = _BodyReader(parser);
    yield body;
    if (body.result is EmptyFunctionBody && !external) {
      parser.error(
        'missing_function_body',
        'A function without external requires a body.',
        Token(.semicolon, parser.source, body.result.start, body.result.end),
      );
    }
    if (external && body.result is! EmptyFunctionBody) {
      parser.error(
        'external_body',
        'An external declaration cannot have a body.',
        Token(.invalid, parser.source, body.result.start, body.result.end),
      );
    }
    if (header.accessor != null && header.typeParameters != null) {
      parser.error(
        'generic_accessor',
        'An accessor cannot declare type parameters.',
        Token(
          .less,
          parser.source,
          header.typeParameters!.start,
          header.typeParameters!.end,
        ),
      );
    }
    final source = parser.source;
    final end = body.result.end;
    result = switch (header.accessor) {
      .keywordGet => TopLevelGetterDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        body: body.result,
      ),
      .keywordSet => TopLevelSetterDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        parameters: parameters!,
        body: body.result,
      ),
      _ => TopLevelFunctionDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: parameters!,
        body: body.result,
      ),
    };
  }

  Iterable<_Reader<Object?>> alias() sync* {
    parser.advance();
    final header = _DeclarationName(parser);
    yield* header.read(alias: true);
    if (parser.current.kind == .assign) {
      parser.advance();
      final typeStart = parser.current.start;
      final reader = _TypeReader(parser);
      if (!reader.start()) yield _TypeTask(reader);
      final type =
          reader.result as TypeAnnotation? ??
          MissingTypeAnnotation(source: parser.source, offset: typeStart);
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
      if (header.type != null) {
        parser.error(
          'invalid_alias',
          'A type alias cannot have a return type before its name.',
          Token(.invalid, parser.source, header.type!.start, header.type!.end),
        );
      }
      result = TypeAliasDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        name: header.name,
        typeParameters: header.typeParameters,
        type: type,
      );
    } else {
      final reader = _ParameterReader(parser, function: true);
      yield reader;
      result = FunctionTypeAliasDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: reader.result,
      );
    }
  }
}
