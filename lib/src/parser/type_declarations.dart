part of 'parser.dart';

enum _TypeDeclarationKind {
  classKind,
  mixin,
  enumKind,
  extension,
  extensionType,
}

final class _TypeDeclarationReader(
  final _Parser parser,
  final int start,
  final List<Annotation> metadata,
) extends _Reader<TopLevelDeclaration> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final modifiers = <ClassModifier>[];
    while (parser.current.kind.classModifier != null) {
      final modifier = parser.current.kind.classModifier!;
      if (modifier == .mixinKeyword &&
          parser.tokens[parser.cursor + 1].kind != .keywordClass) {
        break;
      }
      if (modifiers.contains(modifier)) {
        parser.error(
          'duplicate_modifier',
          'Repeated class modifier.',
          parser.current,
        );
      }
      modifiers.add(modifier);
      parser.advance();
    }
    var kind = switch (parser.current.kind) {
      .keywordMixin => _TypeDeclarationKind.mixin,
      .keywordEnum => _TypeDeclarationKind.enumKind,
      .keywordExtension => _TypeDeclarationKind.extension,
      _ => _TypeDeclarationKind.classKind,
    };
    final validModifiers = switch (kind) {
      .classKind => switch (modifiers) {
        [] ||
        [.abstractKeyword] ||
        [.baseKeyword] ||
        [.interfaceKeyword] ||
        [.finalKeyword] ||
        [.sealedKeyword] ||
        [.mixinKeyword] ||
        [.abstractKeyword, .baseKeyword] ||
        [.abstractKeyword, .interfaceKeyword] ||
        [.abstractKeyword, .finalKeyword] ||
        [.abstractKeyword, .mixinKeyword] ||
        [.baseKeyword, .mixinKeyword] ||
        [.abstractKeyword, .baseKeyword, .mixinKeyword] => true,
        _ => false,
      },
      .mixin =>
        modifiers.isEmpty ||
            modifiers.length == 1 && modifiers.single == .baseKeyword,
      _ => modifiers.isEmpty,
    };
    if (!validModifiers) {
      parser.error(
        'invalid_class_modifiers',
        'Invalid declaration modifier combination.',
        Token(.invalid, parser.source, start, parser.current.start),
      );
    }
    parser.advance();
    if (kind == .extension &&
        parser.current.kind == .keywordType &&
        (parser.tokens[parser.cursor + 1].kind.isIdentifier ||
            parser.tokens[parser.cursor + 1].kind == .keywordConst) &&
        parser.tokens[parser.cursor + 1].kind != .keywordOn) {
      kind = .extensionType;
      parser.advance();
    }
    final isConst = parser.current.kind == .keywordConst;
    if (isConst) parser.advance();
    final name =
        kind == .extension &&
            (parser.current.kind == .keywordOn || parser.current.kind == .less)
        ? null
        : parser.readVariableName();
    final typeParameters = parser.readTypeParameters();
    Identifier? primaryName;
    FormalParameterList? primaryParameters;
    if (parser.current.kind == .dot) {
      parser.advance();
      primaryName = parser.readConstructorName();
    }
    if (parser.current.kind == .leftParen || kind == .extensionType) {
      final reader = _ParameterReader(parser);
      yield reader;
      primaryParameters = reader.result;
    }
    if (isConst && primaryParameters == null) {
      parser.error(
        'missing_primary_parameters',
        'A const declaration requires primary parameters.',
        parser.current,
      );
    }
    if ((kind == .mixin || kind == .extension) &&
        (isConst || primaryName != null || primaryParameters != null)) {
      parser.error(
        'invalid_primary_constructor',
        'This declaration cannot have a primary constructor.',
        parser.current,
      );
    }
    if (primaryName != null && primaryParameters == null) {
      parser.error(
        'missing_primary_parameters',
        'Expected primary constructor parameters.',
        parser.current,
      );
    }
    if (kind == .classKind && parser.current.kind == .assign) {
      parser.advance();
      final superclass = parser.readType();
      final withClause = parser.readTypeListClause(.withKeyword);
      final implementsClause = parser.current.kind == .keywordImplements
          ? parser.readTypeListClause(.implementsKeyword)
          : null;
      result = ClassTypeAliasDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        modifiers: modifiers,
        name: name!,
        typeParameters: typeParameters,
        superclass: superclass,
        withClause: withClause,
        implementsClause: implementsClause,
      );
      return;
    }
    TypeAnnotation? onType;
    ExtendsClause? extendsClause;
    TypeListClause? onClause;
    TypeListClause? withClause;
    TypeListClause? implementsClause;
    if (kind == .extension) {
      parser.expect(.keywordOn);
      onType = parser.readType();
    }
    if (parser.current.kind == .keywordExtends) {
      final token = parser.current;
      parser.advance();
      final type = parser.readType();
      extendsClause = ExtendsClause(
        source: parser.source,
        start: token.start,
        end: type.end,
        superclass: type,
      );
      if (kind != .classKind) {
        parser.error(
          'invalid_extends',
          'Only classes have an extends clause.',
          token,
        );
      }
    }
    if (parser.current.kind == .keywordOn) {
      onClause = parser.readTypeListClause(.onKeyword);
      if (kind != .mixin) {
        parser.error(
          'invalid_on_clause',
          'Only mixins have superclass constraints.',
          parser.current,
        );
      }
    }
    if (parser.current.kind == .keywordWith) {
      withClause = parser.readTypeListClause(.withKeyword);
    }
    if (parser.current.kind == .keywordImplements) {
      implementsClause = parser.readTypeListClause(.implementsKeyword);
    }
    if (withClause != null && kind != .classKind && kind != .enumKind) {
      parser.error(
        'invalid_with_clause',
        'This declaration cannot apply mixins.',
        Token(.keywordWith, parser.source, withClause.start, withClause.end),
      );
    }
    if (implementsClause != null && kind == .extension) {
      parser.error(
        'invalid_implements_clause',
        'An extension cannot implement interfaces.',
        Token(
          .keywordImplements,
          parser.source,
          implementsClause.start,
          implementsClause.end,
        ),
      );
    }
    final body = _MembersReader(parser, name?.text, isEnum: kind == .enumKind);
    yield body;
    final source = parser.source;
    result = switch (kind) {
      .classKind => ClassDeclaration(
        source: source,
        start: start,
        end: body.end,
        metadata: metadata,
        modifiers: modifiers,
        name: name!,
        typeParameters: typeParameters,
        isConst: isConst,
        primaryConstructorName: primaryName,
        primaryParameters: primaryParameters,
        extendsClause: extendsClause,
        withClause: withClause,
        implementsClause: implementsClause,
        isSemicolonBody: body.semicolon,
        members: body.result,
      ),
      .mixin => MixinDeclaration(
        source: source,
        start: start,
        end: body.end,
        metadata: metadata,
        isBase: modifiers.contains(ClassModifier.baseKeyword),
        name: name!,
        typeParameters: typeParameters,
        onClause: onClause,
        implementsClause: implementsClause,
        isSemicolonBody: body.semicolon,
        members: body.result,
      ),
      .enumKind => EnumDeclaration(
        source: source,
        start: start,
        end: body.end,
        metadata: metadata,
        name: name!,
        typeParameters: typeParameters,
        isConst: isConst,
        primaryConstructorName: primaryName,
        primaryParameters: primaryParameters,
        withClause: withClause,
        implementsClause: implementsClause,
        isSemicolonBody: body.semicolon,
        hasMemberSeparator: body.separator,
        constants: body.constants,
        members: body.result,
      ),
      .extension => ExtensionDeclaration(
        source: source,
        start: start,
        end: body.end,
        metadata: metadata,
        name: name,
        typeParameters: typeParameters,
        onType: onType!,
        isSemicolonBody: body.semicolon,
        members: body.result,
      ),
      .extensionType => ExtensionTypeDeclaration(
        source: source,
        start: start,
        end: body.end,
        metadata: metadata,
        isConst: isConst,
        name: name!,
        typeParameters: typeParameters,
        primaryConstructorName: primaryName,
        primaryParameters: primaryParameters!,
        implementsClause: implementsClause,
        isSemicolonBody: body.semicolon,
        members: body.result,
      ),
    };
  }
}

extension on _Parser {
  bool get startsTypeDeclaration {
    var index = cursor;
    while (tokens[index].kind.classModifier != null) {
      if (tokens[index].kind == .keywordMixin) return true;
      index++;
    }
    return switch (tokens[index].kind) {
      .keywordClass || .keywordEnum || .keywordExtension => true,
      _ => false,
    };
  }

  TypeAnnotation readType() {
    final offset = current.start;
    final reader = _TypeReader(this);
    final type = reader.read() as TypeAnnotation?;
    if (reader.failure case final failure?) {
      error(failure.$1, failure.$2, failure.$3);
    }
    return type ?? MissingTypeAnnotation(source: source, offset: offset);
  }

  TypeParameterList? readTypeParameters() {
    if (current.kind != .less) return null;
    final reader = _TypeReader(this);
    final parameters = reader.read(parameters: true) as TypeParameterList?;
    if (reader.failure case final failure?) {
      error(failure.$1, failure.$2, failure.$3);
    }
    return parameters;
  }

  TypeArgumentList? readTypeArguments() {
    if (current.kind != .less) return null;
    final reader = _TypeReader(this);
    final arguments = reader.read(arguments: true) as TypeArgumentList?;
    if (reader.failure case final failure?) {
      error(failure.$1, failure.$2, failure.$3);
    }
    return arguments;
  }

  TypeListClause readTypeListClause(TypeListClauseKind kind) {
    final start = current.start;
    expect(switch (kind) {
      .withKeyword => .keywordWith,
      .implementsKeyword => .keywordImplements,
      .onKeyword => .keywordOn,
    });
    final types = [readType()];
    while (current.kind == .comma) {
      advance();
      types.add(readType());
    }
    return TypeListClause(
      source: source,
      start: start,
      end: types.last.end,
      kind: kind,
      types: types,
    );
  }

  Identifier readConstructorName() {
    if (current.kind != .keywordNew) return readVariableName();
    final token = current;
    advance();
    return Identifier(source: source, start: token.start, end: token.end);
  }
}

extension on TokenKind {
  ClassModifier? get classModifier => switch (this) {
    .keywordAbstract => .abstractKeyword,
    .keywordBase => .baseKeyword,
    .keywordInterface => .interfaceKeyword,
    .keywordFinal => .finalKeyword,
    .keywordSealed => .sealedKeyword,
    .keywordMixin => .mixinKeyword,
    _ => null,
  };
}
