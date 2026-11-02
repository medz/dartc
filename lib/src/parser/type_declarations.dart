part of 'parser.dart';

enum _TypeDeclarationKind {
  classKind,
  mixin,
  enumKind,
  extension,
  extensionType,
}

int _readTypeDeclaration(_Parser parser, int start, List<int> metadata) {
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
  int? typeParameters;
  if (parser.current.kind == .less) {
    final reader = _TypeReader(parser);
    if (!reader.start(parameters: true)) _TypeTask(reader).finish();
    typeParameters = parser.arena.asTypeParameterListOrNull(reader.result);
    if (reader.failure case final failure?) {
      parser.error(failure.$1, failure.$2, failure.$3);
    }
  }
  int? primaryName;
  int? primaryParameters;
  if (parser.current.kind == .dot) {
    parser.advance();
    primaryName = parser.readConstructorName();
  }
  if (parser.current.kind == .leftParen || kind == .extensionType) {
    primaryParameters = _ParameterReader(parser).finish();
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
    final superclass = _RequiredTypeReader(parser).finish();
    final withClause = _readTypeList(parser, .withKeyword);
    int? implementsClause;
    if (parser.current.kind == .keywordImplements) {
      implementsClause = _readTypeList(parser, .implementsKeyword);
    }
    return parser.arena.putClassTypeAliasDeclaration(
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
  }
  int? onType;
  int? extendsClause;
  int? onClause;
  int? withClause;
  int? implementsClause;
  if (kind == .extension) {
    parser.expect(.keywordOn);
    onType = _RequiredTypeReader(parser).finish();
  }
  if (parser.current.kind == .keywordExtends) {
    final token = parser.current;
    parser.advance();
    final type = _RequiredTypeReader(parser).finish();
    extendsClause = parser.arena.putExtendsClause(
      start: token.start,
      end: parser.arena.rEnd(type),
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
    onClause = _readTypeList(parser, .onKeyword);
    if (kind != .mixin) {
      parser.error(
        'invalid_on_clause',
        'Only mixins have superclass constraints.',
        parser.current,
      );
    }
  }
  if (parser.current.kind == .keywordWith) {
    withClause = _readTypeList(parser, .withKeyword);
  }
  if (parser.current.kind == .keywordImplements) {
    implementsClause = _readTypeList(parser, .implementsKeyword);
  }
  if (withClause != null && kind != .classKind && kind != .enumKind) {
    parser.error(
      'invalid_with_clause',
      'This declaration cannot apply mixins.',
      Token(
        .keywordWith,
        parser.source,
        parser.arena.rStart(withClause),
        parser.arena.rEnd(withClause),
      ),
    );
  }
  if (implementsClause != null && kind == .extension) {
    parser.error(
      'invalid_implements_clause',
      'An extension cannot implement interfaces.',
      Token(
        .keywordImplements,
        parser.source,
        parser.arena.rStart(implementsClause),
        parser.arena.rEnd(implementsClause),
      ),
    );
  }
  final body = _MembersReader(parser, parser.arena.rTextOrNull(name), kind);
  final bodyNode = body.read();
  return switch (kind) {
    .classKind => parser.arena.putClassDeclaration(
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
      members: bodyNode,
    ),
    .mixin => parser.arena.putMixinDeclaration(
      start: start,
      end: body.end,
      metadata: metadata,
      isBase: modifiers.contains(ClassModifier.baseKeyword),
      name: name!,
      typeParameters: typeParameters,
      onClause: onClause,
      implementsClause: implementsClause,
      isSemicolonBody: body.semicolon,
      members: bodyNode,
    ),
    .enumKind => parser.arena.putEnumDeclaration(
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
      members: bodyNode,
    ),
    .extension => parser.arena.putExtensionDeclaration(
      start: start,
      end: body.end,
      metadata: metadata,
      name: name,
      typeParameters: typeParameters,
      onType: onType!,
      isSemicolonBody: body.semicolon,
      members: bodyNode,
    ),
    .extensionType => parser.arena.putExtensionTypeDeclaration(
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
      members: bodyNode,
    ),
  };
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

  int readConstructorName() {
    if (current.kind != .keywordNew) return readVariableName();
    final token = current;
    advance();
    return arena.putIdentifier(start: token.start, end: token.end);
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

int _readTypeList(_Parser parser, TypeListClauseKind kind) {
  final start = parser.current.start;
  parser.expect(switch (kind) {
    .withKeyword => .keywordWith,
    .implementsKeyword => .keywordImplements,
    .onKeyword => .keywordOn,
  });
  final types = <int>[];
  do {
    final type = _RequiredTypeReader(parser).finish();
    types.add(type);
    if (parser.current.kind != .comma) break;
    parser.advance();
  } while (true);
  return parser.arena.putTypeListClause(
    start: start,
    end: parser.arena.rEnd(types.last),
    kind: kind,
    types: types,
  );
}
