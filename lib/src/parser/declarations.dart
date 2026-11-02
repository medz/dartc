part of 'parser.dart';

extension on _Parser {
  bool get hasParametersAfterName {
    final next = tokens[cursor + 1].kind;
    if (next == .leftParen) return true;
    if (next != .less) return false;
    final end = lookahead.afterTypeArguments(cursor + 1);
    return end != null && tokens[end].kind == .leftParen;
  }
}

final class _DeclarationName(final _Parser parser) {
  int? type;
  late int name;
  TokenKind? accessor;
  int? typeParameters;
  DeclaredOperator? op;

  void read({bool alias = false, bool member = false}) {
    final initial = parser.cursor;
    final first = parser.current;
    if (!(first.kind == .keywordGet || first.kind == .keywordSet) &&
        parser.canStartTypeBeforeName()) {
      final reader = _TypeReader(parser, beforeFunction: true);
      if (!reader.start()) _TypeTask(reader).finish();
      final parsed = parser.arena.asTypeAnnotationOrNull(reader.result);
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
      if (!reader.start(parameters: true)) _TypeTask(reader).finish();
      typeParameters = parser.arena.asTypeParameterListOrNull(reader.result);
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
  }
}

final class _TopLevelReader(
  final _Parser parser,
  final int start,
  final List<int> metadata,
) {
  int read() {
    if (parser.startsTypeDeclaration) {
      return _readTypeDeclaration(parser, start, metadata);
    }
    if (parser.current.kind == .keywordTypedef &&
        !parser.hasParametersAfterName) {
      return alias();
    }
    final external =
        parser.current.kind == .keywordExternal &&
        !parser.hasParametersAfterName;
    if (external) parser.advance();
    _VariableDeclarations? variables;
    if (parser.canStartVariableDeclaration) {
      variables = _VariableReader(parser, allowConditional: false).finish();
    }
    if (variables case final declarations?) {
      final list = _VariablesReader(
        parser,
        declarations,
        metadata: metadata,
      ).finish();
      return parser.arena.putTopLevelVariableDeclaration(
        start: start,
        end: parser.expect(.semicolon),
        isExternal: external,
        variables: list,
      );
    }
    final initial = parser.cursor;
    final header = _DeclarationName(parser);
    header.read();
    if (parser.arena.rStart(header.name) == parser.arena.rEnd(header.name)) {
      parser.error(
        'expected_declaration',
        'Expected a top-level declaration.',
        parser.current,
      );
      if (parser.cursor == initial && parser.current.kind != .eof) {
        parser.advance();
      }
      return parser.arena.putMissingTopLevelDeclaration(offset: start);
    }
    int? parameters;
    if (header.accessor != .keywordGet) {
      parameters = _ParameterReader(
        parser,
        function: true,
        allowCovariant: false,
      ).finish();
      if (header.accessor == .keywordSet) {
        parser.checkSetterParameters(parameters);
      }
    }
    final body = _BodyReader(parser);
    final bodyNode = body.finish();
    if (parser.arena.hasKind(bodyNode, .emptyFunctionBody) && !external) {
      parser.error(
        'missing_function_body',
        'A function without external requires a body.',
        Token(
          .semicolon,
          parser.source,
          parser.arena.rStart(bodyNode),
          parser.arena.rEnd(bodyNode),
        ),
      );
    }
    if (external && !parser.arena.hasKind(bodyNode, .emptyFunctionBody)) {
      parser.error(
        'external_body',
        'An external declaration cannot have a body.',
        Token(
          .invalid,
          parser.source,
          parser.arena.rStart(bodyNode),
          parser.arena.rEnd(bodyNode),
        ),
      );
    }
    if (header.accessor != null && header.typeParameters != null) {
      parser.error(
        'generic_accessor',
        'An accessor cannot declare type parameters.',
        Token(
          .less,
          parser.source,
          parser.arena.rStart(header.typeParameters!),
          parser.arena.rEnd(header.typeParameters!),
        ),
      );
    }
    final end = parser.arena.rEnd(bodyNode);
    return switch (header.accessor) {
      .keywordGet => parser.arena.putTopLevelGetterDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        body: bodyNode,
      ),
      .keywordSet => parser.arena.putTopLevelSetterDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        parameters: parameters!,
        body: bodyNode,
      ),
      _ => parser.arena.putTopLevelFunctionDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: parameters!,
        body: bodyNode,
      ),
    };
  }

  int alias() {
    parser.advance();
    final header = _DeclarationName(parser);
    header.read(alias: true);
    if (parser.current.kind == .assign) {
      parser.advance();
      final typeStart = parser.current.start;
      final reader = _TypeReader(parser);
      if (!reader.start()) _TypeTask(reader).finish();
      final type =
          parser.arena.asTypeAnnotationOrNull(reader.result) ??
          parser.arena.putMissingTypeAnnotation(offset: typeStart);
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
      if (header.type != null) {
        parser.error(
          'invalid_alias',
          'A type alias cannot have a return type before its name.',
          Token(
            .invalid,
            parser.source,
            parser.arena.rStart(header.type!),
            parser.arena.rEnd(header.type!),
          ),
        );
      }
      return parser.arena.putTypeAliasDeclaration(
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        name: header.name,
        typeParameters: header.typeParameters,
        type: type,
      );
    } else {
      final formals = _ParameterReader(parser, function: true).finish();
      return parser.arena.putFunctionTypeAliasDeclaration(
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: formals,
      );
    }
  }
}
