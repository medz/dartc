part of 'parser.dart';

final class _MembersReader(
  final _Parser parser,
  final String? className,
  final _TypeDeclarationKind kind,
) extends _Reader<List<ClassMember>> {
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
    if (kind == .enumKind) {
      while (parser.current.kind != .rightBrace &&
          parser.current.kind != .semicolon &&
          parser.current.kind != .eof) {
        final initial = parser.cursor;
        final start = parser.current.start;
        List<Annotation> metadata = const [];
        if (parser.current.kind == .at) {
          final annotations = _MetadataReader(parser);
          yield annotations;
          metadata = annotations.result;
        }
        final name = parser.readVariableName();
        TypeArgumentList? types;
        if (parser.current.kind == .less) {
          final reader = _TypeReader(parser);
          if (!reader.start(arguments: true)) yield _TypeTask(reader);
          types = reader.result as TypeArgumentList?;
          if (reader.failure case final failure?) {
            parser.error(failure.$1, failure.$2, failure.$3);
          }
        }
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
        } else if (types != null || constructor != null) {
          parser.error(
            'expected_enum_arguments',
            'Expected arguments after the enum type arguments or constructor name.',
            parser.current,
          );
        }
        constants.add(
          EnumConstantDeclaration(
            source: parser.source,
            start: start,
            end: arguments?.end ?? constructor?.end ?? types?.end ?? name.end,
            metadata: metadata,
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
      List<Annotation> metadata = const [];
      if (parser.current.kind == .at) {
        final annotations = _MetadataReader(parser);
        yield annotations;
        metadata = annotations.result;
      }
      final reader = _MemberReader(parser, className, start, metadata, kind);
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
  final _TypeDeclarationKind kind,
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
      if (parser.functionBodyAfterName(allowEmpty: true)) break;
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
    if (isStatic && covariant) {
      parser.error(
        'static_covariant_member',
        'A static member cannot be covariant.',
        Token(.invalid, parser.source, start, parser.current.start),
      );
    }
    if (parser.tokens[index].kind == .keywordConst) index++;
    final token = parser.tokens[index];
    final isConstructor =
        token.kind == .keywordNew ||
        token.kind == .keywordFactory &&
            parser.tokens[index + 1].kind != .less ||
        token.kind == .keywordThis ||
        className != null &&
            index + 1 < parser.tokens.length &&
            token.lexeme == className &&
            (parser.tokens[index + 1].kind == .leftParen ||
                parser.tokens[index + 1].kind == .dot &&
                    index + 3 < parser.tokens.length &&
                    parser.tokens[index + 3].kind == .leftParen);
    if (isConstructor) {
      if (kind == .mixin || kind == .extension) {
        parser.error(
          'constructor_not_allowed',
          'This declaration cannot contain a constructor.',
          token,
        );
      }
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
      if (result
          case ConstructorDeclaration(keyword: .factoryKeyword, :final name)
          when name.isEmpty || name.first.text != className) {
        parser.requireFeature(result, 3, 13, 'Abbreviated constructors');
      }
      return;
    }
    _VariableDeclarations? variables;
    if (parser.canStartVariableDeclaration) {
      final reader = _VariableReader(parser, allowConditional: false);
      yield reader;
      variables = reader.result;
    }
    if (variables case final declarations?) {
      final reader = _VariablesReader(parser, declarations, metadata: metadata);
      yield reader;
      for (final variable in reader.result.declarations) {
        checkMemberName(variable.name);
      }
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
    final header = _DeclarationName(parser);
    yield* header.read(member: true);
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
    if (header.accessor != .keywordOperator) checkMemberName(header.name);
    FormalParameterList? parameters;
    if (header.accessor != .keywordGet) {
      final reader = _ParameterReader(
        parser,
        function: true,
        allowCovariant:
            !isStatic && kind != .extension && kind != .extensionType,
      );
      yield reader;
      parameters = reader.result;
      if (header.accessor == .keywordSet) {
        parser.checkSetterParameters(parameters);
      }
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

  void checkMemberName(Identifier name) {
    if (name.text != className) return;
    parser.error(
      'member_with_class_name',
      'A non-constructor member cannot have the enclosing declaration name.',
      Token(.invalid, parser.source, name.start, name.end),
    );
  }
}
