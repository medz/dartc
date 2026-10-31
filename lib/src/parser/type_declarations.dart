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
    TypeParameterList? typeParameters;
    if (parser.current.kind == .less) {
      final reader = _TypeReader(parser);
      if (!reader.start(parameters: true)) yield _TypeTask(reader);
      typeParameters = reader.result as TypeParameterList?;
      if (reader.failure case final failure?) {
        parser.error(failure.$1, failure.$2, failure.$3);
      }
    }
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
      final superclass = _RequiredTypeReader(parser);
      yield superclass;
      final withClause = _TypeListReader(parser, .withKeyword);
      yield withClause;
      TypeListClause? implementsClause;
      if (parser.current.kind == .keywordImplements) {
        final reader = _TypeListReader(parser, .implementsKeyword);
        yield reader;
        implementsClause = reader.result;
      }
      result = ClassTypeAliasDeclaration(
        source: parser.source,
        start: start,
        end: parser.expect(.semicolon),
        metadata: metadata,
        modifiers: modifiers,
        name: name!,
        typeParameters: typeParameters,
        superclass: superclass.result,
        withClause: withClause.result,
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
      final reader = _RequiredTypeReader(parser);
      yield reader;
      onType = reader.result;
    }
    if (parser.current.kind == .keywordExtends) {
      final token = parser.current;
      parser.advance();
      final reader = _RequiredTypeReader(parser);
      yield reader;
      final type = reader.result;
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
      final reader = _TypeListReader(parser, .onKeyword);
      yield reader;
      onClause = reader.result;
      if (kind != .mixin) {
        parser.error(
          'invalid_on_clause',
          'Only mixins have superclass constraints.',
          parser.current,
        );
      }
    }
    if (parser.current.kind == .keywordWith) {
      final reader = _TypeListReader(parser, .withKeyword);
      yield reader;
      withClause = reader.result;
    }
    if (parser.current.kind == .keywordImplements) {
      final reader = _TypeListReader(parser, .implementsKeyword);
      yield reader;
      implementsClause = reader.result;
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
    final body = _MembersReader(parser, name?.text, kind);
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
    if ((current.kind == .keywordMixin || current.kind == .keywordExtension) &&
        hasParametersAfterName) {
      return false;
    }
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

final class _TypeListReader(final _Parser parser, final TypeListClauseKind kind)
    extends _Reader<TypeListClause> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final start = parser.current.start;
    parser.expect(switch (kind) {
      .withKeyword => .keywordWith,
      .implementsKeyword => .keywordImplements,
      .onKeyword => .keywordOn,
    });
    final types = <TypeAnnotation>[];
    do {
      final reader = _RequiredTypeReader(parser);
      yield reader;
      types.add(reader.result);
      if (parser.current.kind != .comma) break;
      parser.advance();
    } while (true);
    result = TypeListClause(
      source: parser.source,
      start: start,
      end: types.last.end,
      kind: kind,
      types: types,
    );
  }
}
