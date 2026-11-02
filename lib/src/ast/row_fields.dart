import 'package:dartc/source.dart';

import 'nodes.dart';

extension ArenaFields on AstArena {
  int childIndex(int id, int i) => edges.cells[edgeOffsets[id] + i];
  int rStart(int? id) => starts[id!];
  int rEnd(int? id) => ends[id!];
  int rDotShorthandExpressionExpression(int? id) =>
      fields.cells[offsets[id!] + 0];
  int rNullAssertionExpressionOperand(int? id) =>
      fields.cells[offsets[id!] + 0];
  int? rStartOrNull(int? id) => id == null ? null : starts[id];
  int rTypeAliasDeclarationType(int? id) => fields.cells[offsets[id!] + 2];
  int? rAnnotationTypeArguments(int? id) =>
      nullable(fields.cells[offsets[id!] + 0]);
  int rPropertyAccessExpressionProperty(int? id) =>
      fields.cells[offsets[id!] + 1];
  String rText(int? id) => source.text.substring(starts[id!], ends[id]);
  List<int> rArgumentListArguments(int? id) =>
      refList(fields.cells[offsets[id!] + 0]);
  int? rArgumentName(int? id) => nullable(fields.cells[offsets[id!] + 0]);
  int? rLibraryDirectiveName(int? id) =>
      nullable(fields.cells[offsets[id!] + 0]);
  int? rClassDeclarationPrimaryParameters(int? id) =>
      nullable(fields.cells[offsets[id!] + 4]);
  int? rEnumDeclarationTypeParameters(int? id) =>
      nullable(fields.cells[offsets[id!] + 1]);
  int? rEnumDeclarationWithClause(int? id) =>
      nullable(fields.cells[offsets[id!] + 5]);
  int? rEnumDeclarationImplementsClause(int? id) =>
      nullable(fields.cells[offsets[id!] + 6]);
  int? rEnumDeclarationPrimaryParameters(int? id) =>
      nullable(fields.cells[offsets[id!] + 4]);
  int? rEnumConstantDeclarationTypeArguments(int? id) =>
      nullable(fields.cells[offsets[id!] + 1]);
  int? rEnumConstantDeclarationArguments(int? id) =>
      nullable(fields.cells[offsets[id!] + 3]);
  int? rIfStatementCasePattern(int? id) =>
      nullable(fields.cells[offsets[id!] + 1]);
  int? rIfElementCasePattern(int? id) =>
      nullable(fields.cells[offsets[id!] + 1]);
  int rChildcount(int? id) => edgeOffsets[id! + 1] - edgeOffsets[id];
  int rInvocationExpressionCallee(int? id) => fields.cells[offsets[id!] + 0];
  int rPropertyAccessExpressionTarget(int? id) =>
      fields.cells[offsets[id!] + 0];
  int? rNamedTypeAnnotationPrefix(int? id) =>
      nullable(fields.cells[offsets[id!] + 0]);
  int? rEndOrNull(int? id) => id == null ? null : ends[id];
  int rCastExpressionExpression(int? id) => fields.cells[offsets[id!] + 0];
  int rTypeTestExpressionExpression(int? id) => fields.cells[offsets[id!] + 0];
  BinaryOperator rBinaryExpressionOp(int? id) =>
      BinaryOperator.values[fields.cells[offsets[id!] + 1]];
  int? rVariableDeclarationInitializer(int? id) =>
      nullable(fields.cells[offsets[id!] + 1]);
  int rIdentifierExpressionIdentifier(int? id) =>
      fields.cells[offsets[id!] + 0];
  int rBinaryExpressionLeft(int? id) => fields.cells[offsets[id!] + 0];
  int rIndexExpressionTarget(int? id) => fields.cells[offsets[id!] + 0];
  int rTypeInstantiationExpressionExpression(int? id) =>
      fields.cells[offsets[id!] + 0];
  int? rNullAssertionExpressionOperandOrNull(int? id) =>
      id == null ? null : fields.cells[offsets[id] + 0];
  List<int> rFormalParameterListParameters(int? id) =>
      refList(fields.cells[offsets[id!] + 0]);
  FormalParameterKind rFormalParameterKind(int? id) =>
      FormalParameterKind.values[fields.cells[offsets[id!] + 0]];
  String? rTextOrNull(int? id) =>
      id == null ? null : source.text.substring(starts[id], ends[id]);
  List<int> rConstructorDeclarationName(int? id) =>
      refList(fields.cells[offsets[id!] + 6]);
  List<int> rVariableDeclarationListDeclarations(int? id) =>
      refList(fields.cells[offsets[id!] + 4]);
  int rVariableDeclarationName(int? id) => fields.cells[offsets[id!] + 0];
  bool rExpressionFunctionBodyIsAsync(int? id) =>
      (fields.cells[offsets[id!] + 0] == 1);
  int rArgumentValue(int? id) => fields.cells[offsets[id!] + 1];
  int? rNamedTypeAnnotationQuestionOffset(int? id) =>
      nullable(fields.cells[offsets[id!] + 3]);
  bool rNamedTypeAnnotationIsNullable(int? id) =>
      (rNamedTypeAnnotationQuestionOffset(id) != null);
  int? rConstDotShorthandExpressionArguments(int? id) =>
      nullable(fields.cells[offsets[id!] + 2]);
  SourceFile rSource(int? id) => source;
  bool isBinaryExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        8 => true,
        _ => false,
      });
  int asBinaryExpression(Object? v) => isBinaryExpression(v)
      ? v as int
      : throw StateError('Expected BinaryExpression');
  int? asBinaryExpressionOrNull(Object? v) =>
      v == null ? null : asBinaryExpression(v);
  bool isBlockStatement(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        9 => true,
        _ => false,
      });
  int asBlockStatement(Object? v) => isBlockStatement(v)
      ? v as int
      : throw StateError('Expected BlockStatement');
  int? asBlockStatementOrNull(Object? v) =>
      v == null ? null : asBlockStatement(v);
  bool isCascadeExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        11 => true,
        _ => false,
      });
  int asCascadeExpression(Object? v) => isCascadeExpression(v)
      ? v as int
      : throw StateError('Expected CascadeExpression');
  int? asCascadeExpressionOrNull(Object? v) =>
      v == null ? null : asCascadeExpression(v);
  bool isCascadeIndexExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        12 => true,
        _ => false,
      });
  int asCascadeIndexExpression(Object? v) => isCascadeIndexExpression(v)
      ? v as int
      : throw StateError('Expected CascadeIndexExpression');
  int? asCascadeIndexExpressionOrNull(Object? v) =>
      v == null ? null : asCascadeIndexExpression(v);
  bool isCascadePropertyExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        13 => true,
        _ => false,
      });
  int asCascadePropertyExpression(Object? v) => isCascadePropertyExpression(v)
      ? v as int
      : throw StateError('Expected CascadePropertyExpression');
  int? asCascadePropertyExpressionOrNull(Object? v) =>
      v == null ? null : asCascadePropertyExpression(v);
  bool isCastExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        14 => true,
        _ => false,
      });
  int asCastExpression(Object? v) => isCastExpression(v)
      ? v as int
      : throw StateError('Expected CastExpression');
  int? asCastExpressionOrNull(Object? v) =>
      v == null ? null : asCastExpression(v);
  bool isConstDotShorthandExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        23 => true,
        _ => false,
      });
  int asConstDotShorthandExpression(Object? v) =>
      isConstDotShorthandExpression(v)
      ? v as int
      : throw StateError('Expected ConstDotShorthandExpression');
  int? asConstDotShorthandExpressionOrNull(Object? v) =>
      v == null ? null : asConstDotShorthandExpression(v);
  bool isConstantPattern(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        24 => true,
        _ => false,
      });
  int asConstantPattern(Object? v) => isConstantPattern(v)
      ? v as int
      : throw StateError('Expected ConstantPattern');
  int? asConstantPatternOrNull(Object? v) =>
      v == null ? null : asConstantPattern(v);
  bool isDartPattern(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        155 ||
        103 ||
        118 ||
        98 ||
        75 ||
        77 ||
        15 ||
        99 ||
        24 ||
        153 ||
        114 ||
        83 ||
        95 ||
        72 ||
        61 => true,
        _ => false,
      });
  int asDartPattern(Object? v) =>
      isDartPattern(v) ? v as int : throw StateError('Expected DartPattern');
  int? asDartPatternOrNull(Object? v) => v == null ? null : asDartPattern(v);
  bool isDotShorthandExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        29 => true,
        _ => false,
      });
  int asDotShorthandExpression(Object? v) => isDotShorthandExpression(v)
      ? v as int
      : throw StateError('Expected DotShorthandExpression');
  int? asDotShorthandExpressionOrNull(Object? v) =>
      v == null ? null : asDotShorthandExpression(v);
  bool isDotShorthandReferenceExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        30 => true,
        _ => false,
      });
  int asDotShorthandReferenceExpression(Object? v) =>
      isDotShorthandReferenceExpression(v)
      ? v as int
      : throw StateError('Expected DotShorthandReferenceExpression');
  int? asDotShorthandReferenceExpressionOrNull(Object? v) =>
      v == null ? null : asDotShorthandReferenceExpression(v);
  bool isEmptyFunctionBody(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        32 => true,
        _ => false,
      });
  int asEmptyFunctionBody(Object? v) => isEmptyFunctionBody(v)
      ? v as int
      : throw StateError('Expected EmptyFunctionBody');
  int? asEmptyFunctionBodyOrNull(Object? v) =>
      v == null ? null : asEmptyFunctionBody(v);
  bool isExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        96 ||
        126 ||
        7 ||
        73 ||
        21 ||
        11 ||
        65 ||
        68 ||
        81 ||
        149 ||
        129 ||
        102 ||
        51 ||
        6 ||
        12 ||
        112 ||
        29 ||
        23 ||
        19 ||
        67 ||
        30 ||
        14 ||
        134 ||
        130 ||
        148 ||
        0 ||
        8 ||
        143 ||
        60 ||
        147 ||
        113 ||
        66 ||
        85 ||
        13 ||
        135 ||
        106 => true,
        _ => false,
      });
  int asExpression(Object? v) =>
      isExpression(v) ? v as int : throw StateError('Expected Expression');
  int? asExpressionOrNull(Object? v) => v == null ? null : asExpression(v);
  bool isExpressionFunctionBody(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        37 => true,
        _ => false,
      });
  int asExpressionFunctionBody(Object? v) => isExpressionFunctionBody(v)
      ? v as int
      : throw StateError('Expected ExpressionFunctionBody');
  int? asExpressionFunctionBodyOrNull(Object? v) =>
      v == null ? null : asExpressionFunctionBody(v);
  bool isForInParts(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        46 => true,
        _ => false,
      });
  int asForInParts(Object? v) =>
      isForInParts(v) ? v as int : throw StateError('Expected ForInParts');
  int? asForInPartsOrNull(Object? v) => v == null ? null : asForInParts(v);
  bool isFunctionTypeAnnotation(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        54 => true,
        _ => false,
      });
  int asFunctionTypeAnnotation(Object? v) => isFunctionTypeAnnotation(v)
      ? v as int
      : throw StateError('Expected FunctionTypeAnnotation');
  int? asFunctionTypeAnnotationOrNull(Object? v) =>
      v == null ? null : asFunctionTypeAnnotation(v);
  bool isIdentifierExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        60 => true,
        _ => false,
      });
  int asIdentifierExpression(Object? v) => isIdentifierExpression(v)
      ? v as int
      : throw StateError('Expected IdentifierExpression');
  int? asIdentifierExpressionOrNull(Object? v) =>
      v == null ? null : asIdentifierExpression(v);
  bool isIdentifierPattern(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        61 => true,
        _ => false,
      });
  int asIdentifierPattern(Object? v) => isIdentifierPattern(v)
      ? v as int
      : throw StateError('Expected IdentifierPattern');
  int? asIdentifierPatternOrNull(Object? v) =>
      v == null ? null : asIdentifierPattern(v);
  bool isIndexExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        65 => true,
        _ => false,
      });
  int asIndexExpression(Object? v) => isIndexExpression(v)
      ? v as int
      : throw StateError('Expected IndexExpression');
  int? asIndexExpressionOrNull(Object? v) =>
      v == null ? null : asIndexExpression(v);
  bool isMissingExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        81 => true,
        _ => false,
      });
  int asMissingExpression(Object? v) => isMissingExpression(v)
      ? v as int
      : throw StateError('Expected MissingExpression');
  int? asMissingExpressionOrNull(Object? v) =>
      v == null ? null : asMissingExpression(v);
  bool isModifiedBlockFunctionBody(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        89 => true,
        _ => false,
      });
  int asModifiedBlockFunctionBody(Object? v) => isModifiedBlockFunctionBody(v)
      ? v as int
      : throw StateError('Expected ModifiedBlockFunctionBody');
  int? asModifiedBlockFunctionBodyOrNull(Object? v) =>
      v == null ? null : asModifiedBlockFunctionBody(v);
  bool isNamedTypeAnnotation(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        93 => true,
        _ => false,
      });
  int asNamedTypeAnnotation(Object? v) => isNamedTypeAnnotation(v)
      ? v as int
      : throw StateError('Expected NamedTypeAnnotation');
  int? asNamedTypeAnnotationOrNull(Object? v) =>
      v == null ? null : asNamedTypeAnnotation(v);
  bool isNullAssertionExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        96 => true,
        _ => false,
      });
  int asNullAssertionExpression(Object? v) => isNullAssertionExpression(v)
      ? v as int
      : throw StateError('Expected NullAssertionExpression');
  int? asNullAssertionExpressionOrNull(Object? v) =>
      v == null ? null : asNullAssertionExpression(v);
  bool isPropertyAccessExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        112 => true,
        _ => false,
      });
  int asPropertyAccessExpression(Object? v) => isPropertyAccessExpression(v)
      ? v as int
      : throw StateError('Expected PropertyAccessExpression');
  int? asPropertyAccessExpressionOrNull(Object? v) =>
      v == null ? null : asPropertyAccessExpression(v);
  bool isRecordTypeAnnotation(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        115 => true,
        _ => false,
      });
  int asRecordTypeAnnotation(Object? v) => isRecordTypeAnnotation(v)
      ? v as int
      : throw StateError('Expected RecordTypeAnnotation');
  int? asRecordTypeAnnotationOrNull(Object? v) =>
      v == null ? null : asRecordTypeAnnotation(v);
  bool isRelationalPattern(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        118 => true,
        _ => false,
      });
  int asRelationalPattern(Object? v) => isRelationalPattern(v)
      ? v as int
      : throw StateError('Expected RelationalPattern');
  int? asRelationalPatternOrNull(Object? v) =>
      v == null ? null : asRelationalPattern(v);
  bool isStringExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        126 || 67 || 0 || 85 => true,
        _ => false,
      });
  int asStringExpression(Object? v) => isStringExpression(v)
      ? v as int
      : throw StateError('Expected StringExpression');
  int? asStringExpressionOrNull(Object? v) =>
      v == null ? null : asStringExpression(v);
  bool isStringInterpolation(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        125 => true,
        _ => false,
      });
  int asStringInterpolation(Object? v) => isStringInterpolation(v)
      ? v as int
      : throw StateError('Expected StringInterpolation');
  int? asStringInterpolationOrNull(Object? v) =>
      v == null ? null : asStringInterpolation(v);
  bool isSuperExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        129 => true,
        _ => false,
      });
  int asSuperExpression(Object? v) => isSuperExpression(v)
      ? v as int
      : throw StateError('Expected SuperExpression');
  int? asSuperExpressionOrNull(Object? v) =>
      v == null ? null : asSuperExpression(v);
  bool isThisExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        134 => true,
        _ => false,
      });
  int asThisExpression(Object? v) => isThisExpression(v)
      ? v as int
      : throw StateError('Expected ThisExpression');
  int? asThisExpressionOrNull(Object? v) =>
      v == null ? null : asThisExpression(v);
  bool isTypeAnnotation(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        54 || 93 || 87 || 115 => true,
        _ => false,
      });
  int asTypeAnnotation(Object? v) => isTypeAnnotation(v)
      ? v as int
      : throw StateError('Expected TypeAnnotation');
  int? asTypeAnnotationOrNull(Object? v) =>
      v == null ? null : asTypeAnnotation(v);
  bool isTypeArgumentList(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        142 => true,
        _ => false,
      });
  int asTypeArgumentList(Object? v) => isTypeArgumentList(v)
      ? v as int
      : throw StateError('Expected TypeArgumentList');
  int? asTypeArgumentListOrNull(Object? v) =>
      v == null ? null : asTypeArgumentList(v);
  bool isTypeParameterList(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        146 => true,
        _ => false,
      });
  int asTypeParameterList(Object? v) => isTypeParameterList(v)
      ? v as int
      : throw StateError('Expected TypeParameterList');
  int? asTypeParameterListOrNull(Object? v) =>
      v == null ? null : asTypeParameterList(v);
  bool isTypeTestExpression(Object? v) =>
      v is int &&
      (switch (tags[v]) {
        147 => true,
        _ => false,
      });
  int asTypeTestExpression(Object? v) => isTypeTestExpression(v)
      ? v as int
      : throw StateError('Expected TypeTestExpression');
  int? asTypeTestExpressionOrNull(Object? v) =>
      v == null ? null : asTypeTestExpression(v);
}

extension TypeAliasDeclarationRowFields on TypeAliasDeclaration {
  int get refType {
    final (arena, id) = AstArena.locate(this);
    return arena.rTypeAliasDeclarationType(id);
  }
}

extension AnnotationRowFields on Annotation {
  int? get refTypeArguments {
    final (arena, id) = AstArena.locate(this);
    return arena.rAnnotationTypeArguments(id);
  }
}

extension PropertyAccessExpressionRowFields on PropertyAccessExpression {
  int get refProperty {
    final (arena, id) = AstArena.locate(this);
    return arena.rPropertyAccessExpressionProperty(id);
  }

  int get refTarget {
    final (arena, id) = AstArena.locate(this);
    return arena.rPropertyAccessExpressionTarget(id);
  }
}

extension ArgumentListRowFields on ArgumentList {
  List<int> get refArguments {
    final (arena, id) = AstArena.locate(this);
    return arena.rArgumentListArguments(id);
  }
}

extension LibraryDirectiveRowFields on LibraryDirective {
  int? get refName {
    final (arena, id) = AstArena.locate(this);
    return arena.rLibraryDirectiveName(id);
  }
}

extension ClassDeclarationRowFields on ClassDeclaration {
  int? get refPrimaryParameters {
    final (arena, id) = AstArena.locate(this);
    return arena.rClassDeclarationPrimaryParameters(id);
  }
}

extension EnumDeclarationRowFields on EnumDeclaration {
  int? get refTypeParameters {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumDeclarationTypeParameters(id);
  }

  int? get refWithClause {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumDeclarationWithClause(id);
  }

  int? get refImplementsClause {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumDeclarationImplementsClause(id);
  }

  int? get refPrimaryParameters {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumDeclarationPrimaryParameters(id);
  }
}

extension EnumConstantDeclarationRowFields on EnumConstantDeclaration {
  int? get refTypeArguments {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumConstantDeclarationTypeArguments(id);
  }

  int? get refArguments {
    final (arena, id) = AstArena.locate(this);
    return arena.rEnumConstantDeclarationArguments(id);
  }
}

extension IfStatementRowFields on IfStatement {
  int? get refCasePattern {
    final (arena, id) = AstArena.locate(this);
    return arena.rIfStatementCasePattern(id);
  }
}

extension IfElementRowFields on IfElement {
  int? get refCasePattern {
    final (arena, id) = AstArena.locate(this);
    return arena.rIfElementCasePattern(id);
  }
}

extension InvocationExpressionRowFields on InvocationExpression {
  int get refCallee {
    final (arena, id) = AstArena.locate(this);
    return arena.rInvocationExpressionCallee(id);
  }
}

extension CastExpressionRowFields on CastExpression {
  int get refExpression {
    final (arena, id) = AstArena.locate(this);
    return arena.rCastExpressionExpression(id);
  }
}

extension TypeTestExpressionRowFields on TypeTestExpression {
  int get refExpression {
    final (arena, id) = AstArena.locate(this);
    return arena.rTypeTestExpressionExpression(id);
  }
}

extension IdentifierExpressionRowFields on IdentifierExpression {
  int get refIdentifier {
    final (arena, id) = AstArena.locate(this);
    return arena.rIdentifierExpressionIdentifier(id);
  }
}

extension BinaryExpressionRowFields on BinaryExpression {
  int get refLeft {
    final (arena, id) = AstArena.locate(this);
    return arena.rBinaryExpressionLeft(id);
  }
}

extension NullAssertionExpressionRowFields on NullAssertionExpression {
  int get refOperand {
    final (arena, id) = AstArena.locate(this);
    return arena.rNullAssertionExpressionOperand(id);
  }
}

extension IndexExpressionRowFields on IndexExpression {
  int get refTarget {
    final (arena, id) = AstArena.locate(this);
    return arena.rIndexExpressionTarget(id);
  }
}

extension TypeInstantiationExpressionRowFields on TypeInstantiationExpression {
  int get refExpression {
    final (arena, id) = AstArena.locate(this);
    return arena.rTypeInstantiationExpressionExpression(id);
  }
}

extension ConstructorDeclarationRowFields on ConstructorDeclaration {
  List<int> get refName {
    final (arena, id) = AstArena.locate(this);
    return arena.rConstructorDeclarationName(id);
  }
}

extension ConstDotShorthandExpressionRowFields on ConstDotShorthandExpression {
  int? get refArguments {
    final (arena, id) = AstArena.locate(this);
    return arena.rConstDotShorthandExpressionArguments(id);
  }
}
