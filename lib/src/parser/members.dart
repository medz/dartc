part of 'parser.dart';

final class _MembersReader(
  final _Parser parser,
  final String? className,
  final _TypeDeclarationKind kind,
) {
  late int end;
  bool semicolon = false;
  bool separator = false;
  final List<int> constants = [];

  List<int> read() {
    final result = <int>[];
    if (parser.current.kind == .semicolon) {
      semicolon = true;
      end = parser.current.end;
      parser.advance();
      return result;
    }
    parser.expect(.leftBrace);
    if (kind == .enumKind) {
      while (parser.current.kind != .rightBrace &&
          parser.current.kind != .semicolon &&
          parser.current.kind != .eof) {
        final initial = parser.cursor;
        final start = parser.current.start;
        List<int> metadata = const [];
        if (parser.current.kind == .at) {
          metadata = _MetadataReader(parser).finish();
        }
        final name = parser.readVariableName();
        int? types;
        if (parser.current.kind == .less) {
          final reader = _TypeReader(parser);
          if (!reader.start(arguments: true)) _TypeTask(reader).finish();
          types = parser.arena.asTypeArgumentListOrNull(reader.result);
          if (reader.failure case final failure?) {
            parser.error(failure.$1, failure.$2, failure.$3);
          }
        }
        int? constructor;
        if (parser.current.kind == .dot) {
          parser.advance();
          constructor = parser.readConstructorName();
        }
        int? arguments;
        if (parser.current.kind == .leftParen) {
          arguments = _ArgumentsReader(parser).finish();
        } else if (types != null || constructor != null) {
          parser.error(
            'expected_enum_arguments',
            'Expected arguments after the enum type arguments or constructor name.',
            parser.current,
          );
        }
        constants.add(
          parser.arena.putEnumConstantDeclaration(
            start: start,
            end:
                parser.arena.rEndOrNull(arguments) ??
                parser.arena.rEndOrNull(constructor) ??
                parser.arena.rEndOrNull(types) ??
                parser.arena.rEnd(name),
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
      List<int> metadata = const [];
      if (parser.current.kind == .at) {
        metadata = _MetadataReader(parser).finish();
      }
      final member = _MemberReader(
        parser,
        className,
        start,
        metadata,
        kind,
      ).read();
      result.add(member);
      if (parser.cursor == initial) parser.unexpected();
    }
    end = parser.expect(.rightBrace);
    return result;
  }
}

final class _MemberReader(
  final _Parser parser,
  final String? className,
  final int start,
  final List<int> metadata,
  final _TypeDeclarationKind kind,
) {
  int read() {
    const externalBit = 1, staticBit = 2, abstractBit = 4, covariantBit = 8;
    var modifiers = 0;
    while (true) {
      final token = parser.current;
      final bit = switch (token.kind) {
        .keywordExternal => externalBit,
        .keywordStatic => staticBit,
        .keywordAbstract => abstractBit,
        .keywordCovariant => covariantBit,
        _ => 0,
      };
      if (bit == 0 || parser.functionBodyAfterName(allowEmpty: true)) break;
      if (modifiers & bit != 0) {
        parser.error('duplicate_modifier', 'Repeated member modifier.', token);
      }
      modifiers |= bit;
      parser.advance();
    }
    final external = modifiers & externalBit != 0;
    final isStatic = modifiers & staticBit != 0;
    final isAbstract = modifiers & abstractBit != 0;
    final covariant = modifiers & covariantBit != 0;
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
            (parser.tokens[index + 1].kind == .leftParen ||
                parser.tokens[index + 1].kind == .dot &&
                    index + 3 < parser.tokens.length &&
                    parser.tokens[index + 3].kind == .leftParen) &&
            hasClassName(token.start, token.end);
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

      final result = _readConstructor(
        parser,
        start,
        metadata,
        external: external,
      );
      if (parser.before(3, 13)) {
        final member = parser.arena.at(result);
        if (member
            case ConstructorDeclaration(keyword: .factoryKeyword, :final name)
            when name.isEmpty || name.first.text != className) {
          parser.requireFeature(member, 3, 13, 'Abbreviated constructors');
        }
      }
      return result;
    }
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
      for (final variable in declarations.variables) {
        checkMemberName(parser.arena.rVariableDeclarationName(variable));
      }
      return parser.arena.putFieldDeclaration(
        start: start,
        end: parser.expect(.semicolon),
        isStatic: isStatic,
        isAbstract: isAbstract,
        isExternal: external,
        isCovariant: covariant,
        variables: list,
      );
    }
    final header = _DeclarationName(parser);
    header.read(member: true);
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
        parser.arena.rStart(header.name) == parser.arena.rEnd(header.name)) {
      parser.error(
        'expected_member',
        'Expected a class member.',
        parser.current,
      );
      return parser.arena.putMissingClassMember(offset: start);
    }
    if (header.accessor != .keywordOperator) checkMemberName(header.name);
    int? parameters;
    if (header.accessor != .keywordGet) {
      parameters = _ParameterReader(
        parser,
        function: true,
        allowCovariant:
            !isStatic && kind != .extension && kind != .extensionType,
      ).finish();
      if (header.accessor == .keywordSet) {
        parser.checkSetterParameters(parameters);
      }
    }
    final body = _BodyReader(parser);
    final bodyNode = body.finish();
    if (external && !parser.arena.hasKind(bodyNode, .emptyFunctionBody)) {
      parser.error(
        'external_body',
        'An external member cannot have a body.',
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
    if (isStatic &&
        !external &&
        parser.arena.hasKind(bodyNode, .emptyFunctionBody)) {
      parser.error(
        'missing_function_body',
        'A static member requires a body.',
        Token(
          .semicolon,
          parser.source,
          parser.arena.rStart(bodyNode),
          parser.arena.rEnd(bodyNode),
        ),
      );
    }
    final end = parser.arena.rEnd(bodyNode);
    return switch (header.accessor) {
      .keywordGet => parser.arena.putGetterDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        returnType: header.type,
        name: header.name,
        body: bodyNode,
      ),
      .keywordSet => parser.arena.putSetterDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        isCovariant: covariant,
        returnType: header.type,
        name: header.name,
        parameters: parameters!,
        body: bodyNode,
      ),
      .keywordOperator when header.op != null =>
        parser.arena.putOperatorDeclaration(
          start: start,
          end: end,
          metadata: metadata,
          isExternal: external,
          isStatic: isStatic,
          returnType: header.type,
          op: header.op!,
          parameters: parameters!,
          body: bodyNode,
        ),
      .keywordOperator => parser.arena.putMissingClassMember(offset: start),
      _ => parser.arena.putMethodDeclaration(
        start: start,
        end: end,
        metadata: metadata,
        isExternal: external,
        isStatic: isStatic,
        returnType: header.type,
        name: header.name,
        typeParameters: header.typeParameters,
        parameters: parameters!,
        body: bodyNode,
      ),
    };
  }

  bool hasClassName(int start, int end) {
    final name = className;
    return name != null &&
        end - start == name.length &&
        parser.source.text.startsWith(name, start);
  }

  void checkMemberName(int name) {
    if (!hasClassName(parser.arena.rStart(name), parser.arena.rEnd(name))) {
      return;
    }
    parser.error(
      'member_with_class_name',
      'A non-constructor member cannot have the enclosing declaration name.',
      Token(
        .invalid,
        parser.source,
        parser.arena.rStart(name),
        parser.arena.rEnd(name),
      ),
    );
  }
}
