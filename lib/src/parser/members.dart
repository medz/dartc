part of 'parser.dart';

final class _MembersReader(
  final _Parser parser,
  final String? className, {
  final bool isEnum = false,
}) extends _Reader<List<ClassMember>> {
  late int end;
  bool semicolon = false;
  bool separator = false;
  final List<EnumConstantDeclaration> constants = [];

  @override
  Iterable<_Reader<Object?>> read() sync* {
    result = [];
    if (parser.current.kind == .semicolon) {
      semicolon = true;
      end = parser.current.end;
      parser.advance();
      return;
    }
    parser.expect(.leftBrace);
    if (isEnum) {
      while (parser.current.kind != .rightBrace &&
          parser.current.kind != .semicolon &&
          parser.current.kind != .eof) {
        final initial = parser.cursor;
        final start = parser.current.start;
        final annotations = _MetadataReader(parser);
        yield annotations;
        final name = parser.readVariableName();
        final types = parser.readTypeArguments();
        Identifier? constructor;
        if (parser.current.kind == .dot) {
          parser.advance();
          constructor = parser.readConstructorName();
        }
        ArgumentList? arguments;
        if (parser.current.kind == .leftParen) {
          final reader = _ArgumentsReader(parser);
          yield reader;
          arguments = reader.result;
        }
        constants.add(
          EnumConstantDeclaration(
            source: parser.source,
            start: start,
            end: arguments?.end ?? constructor?.end ?? types?.end ?? name.end,
            metadata: annotations.result,
            name: name,
            typeArguments: types,
            constructorName: constructor,
            arguments: arguments,
          ),
        );
        if (parser.current.kind != .comma) break;
        parser.advance();
        if (parser.cursor == initial) break;
      }
      if (parser.current.kind == .semicolon) {
        separator = true;
        parser.advance();
      } else if (parser.current.kind != .rightBrace) {
        parser.expect(.rightBrace);
      }
    }
    while (parser.current.kind != .rightBrace && parser.current.kind != .eof) {
      final initial = parser.cursor;
      final start = parser.current.start;
      final annotations = _MetadataReader(parser);
      yield annotations;
      final reader = _MemberReader(
        parser,
        className,
        start,
        annotations.result,
      );
      yield reader;
      result.add(reader.result);
      if (parser.cursor == initial) parser.unexpected();
    }
    end = parser.expect(.rightBrace);
  }
}

final class _MemberReader(
  final _Parser parser,
  final String? className,
  final int start,
  final List<Annotation> metadata,
) extends _Reader<ClassMember> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    var external = false;
    var isStatic = false;
    var isAbstract = false;
    var covariant = false;
    final modifiers = <TokenKind>{};
    while (parser.current.kind == .keywordExternal ||
        parser.current.kind == .keywordStatic ||
        parser.current.kind == .keywordAbstract ||
        parser.current.kind == .keywordCovariant) {
      final token = parser.current;
      if (parser.tokens[parser.cursor + 1].kind == .leftParen) break;
      if (!modifiers.add(token.kind)) {
        parser.error('duplicate_modifier', 'Repeated member modifier.', token);
      }
      switch (token.kind) {
        case .keywordExternal:
          external = true;
        case .keywordStatic:
          isStatic = true;
        case .keywordAbstract:
          isAbstract = true;
        case .keywordCovariant:
          covariant = true;
        default:
          break;
      }
      parser.advance();
    }
    var index = parser.cursor;
    if (parser.tokens[index].kind == .keywordConst) index++;
    final token = parser.tokens[index];
    final isConstructor =
        token.kind == .keywordNew ||
        token.kind == .keywordFactory ||
        token.kind == .keywordThis ||
        className != null &&
            index + 1 < parser.tokens.length &&
            token.lexeme == className &&
            (parser.tokens[index + 1].kind == .leftParen ||
                parser.tokens[index + 1].kind == .dot &&
                    index + 3 < parser.tokens.length &&
                    parser.tokens[index + 3].kind == .leftParen);
    if (isConstructor) {
      if (isStatic || isAbstract || covariant) {
        parser.error(
          'invalid_constructor_modifier',
          'This modifier is not allowed on a constructor.',
          token,
        );
      }

      final reader = _ConstructorReader(
        parser,
        start,
        metadata,
        external: external,
      );
      yield reader;
      result = reader.result;
      return;
    }
    final variable = _VariableReader(parser, allowConditional: false);
    final complete = variable.start();
    assert(complete);
    if (variable.result case final declarations?) {
      final reader = _VariablesReader(parser, declarations, metadata: metadata);
      yield reader;
      result = FieldDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        isStatic: isStatic,
        isAbstract: isAbstract,
        isExternal: external,
        isCovariant: covariant,
        variables: reader.result,
      );
      return;
    }
    final header = _DeclarationName(parser)..read(member: true);
    if (isAbstract || covariant && header.accessor != .keywordSet) {
      parser.error(
        'invalid_member_modifier',
        'This modifier is not allowed on this member.',
        Token(.invalid, parser.source, start, parser.current.start),
      );
    }
    if (isStatic && header.accessor == .keywordOperator) {
      parser.error(
        'static_operator',
        'An operator cannot be static.',
        Token(.invalid, parser.source, start, parser.current.start),
      );
    }
    if (header.accessor != .keywordOperator &&
        header.name.start == header.name.end) {
      parser.error(
        'expected_member',
        'Expected a class member.',
        parser.current,
      );
      result = MissingClassMember(source: parser.source, offset: start);
      return;
    }
    FormalParameterList? parameters;
    if (header.accessor != .keywordGet) {
      final reader = _ParameterReader(parser, function: true);
      yield reader;
      parameters = reader.result;
    }
    final body = _BodyReader(parser);
    yield body;
    if (external && body.result is! EmptyFunctionBody) {
      parser.error(
        'external_body',
        'An external member cannot have a body.',
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
    if (isStatic && !external && body.result is EmptyFunctionBody) {
      parser.error(
        'missing_function_body',
        'A static member requires a body.',
        Token(.semicolon, parser.source, body.result.start, body.result.end),
      );
    }
    final source = parser.source;
    final end = body.result.end;
    result = switch (header.accessor) {
      .keywordGet => GetterDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        returnType: header.type,
        name: header.name,
        body: body.result,
      ),
      .keywordSet => SetterDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        isCovariant: covariant,
        returnType: header.type,
        name: header.name,
        parameters: parameters!,
        body: body.result,
      ),
      .keywordOperator when header.op != null => OperatorDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        returnType: header.type,
        op: header.op!,
        parameters: parameters!,
        body: body.result,
      ),
      .keywordOperator => MissingClassMember(source: source, offset: start),
      _ => MethodDeclaration(
        source: source,
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: parameters!,
        body: body.result,
      ),
    };
  }
}
