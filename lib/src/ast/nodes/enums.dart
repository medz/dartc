part of '../nodes.dart';

/// An enum declaration with its written constants, header, and members.
///
/// Constants retain their written arguments. No implicit constructor, index,
/// name string, superclass, or `values` member is added to the syntax tree.
final class EnumDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The declared enum name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// Whether `const` is written before the primary constructor name.
  final bool isConst = false,

  /// The primary constructor's written suffix, including `new`, or `null`.
  final Identifier? primaryConstructorName,

  /// The primary constructor parameters, or `null` when no header is written.
  final FormalParameterList? primaryParameters,

  /// The written mixin applications, or `null` when omitted.
  final TypeListClause? withClause,

  /// The written implemented interfaces, or `null` when omitted.
  final TypeListClause? implementsClause,

  /// Whether the declaration ends with `;` instead of a braced body.
  final bool isSemicolonBody = false,

  /// Whether a semicolon separates constants from members inside the braces.
  final bool hasMemberSeparator = false,

  List<EnumConstantDeclaration> constants = const [],
  List<ClassMember> members = const [],
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written enum constants, copied into an unmodifiable list.
  final List<EnumConstantDeclaration> constants = _freeze(constants);

  /// The written members after the constants, in an unmodifiable list.
  final List<ClassMember> members = _freeze(members);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      1 +
      (typeParameters == null ? 0 : 1) +
      (primaryConstructorName == null ? 0 : 1) +
      (primaryParameters == null ? 0 : 1) +
      (withClause == null ? 0 : 1) +
      (implementsClause == null ? 0 : 1) +
      constants.length +
      members.length;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index == 0) return name;
    index--;
    if (typeParameters != null) {
      if (index == 0) return typeParameters!;
      index--;
    }
    if (primaryConstructorName != null) {
      if (index == 0) return primaryConstructorName!;
      index--;
    }
    if (primaryParameters != null) {
      if (index == 0) return primaryParameters!;
      index--;
    }
    if (withClause != null) {
      if (index == 0) return withClause!;
      index--;
    }
    if (implementsClause != null) {
      if (index == 0) return implementsClause!;
      index--;
    }
    if (index < constants.length) return constants[index];
    return members[index - constants.length];
  }
}

/// One enum constant with its written metadata and optional constructor call.
final class EnumConstantDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The declared constant name.
  required final Identifier name,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  /// The written constructor suffix, including `new`, or `null` when omitted.
  final Identifier? constructorName,

  /// The written argument list, or `null` when parentheses are absent.
  final ArgumentList? arguments,
}) extends AstNode {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      1 +
      (typeArguments == null ? 0 : 1) +
      (constructorName == null ? 0 : 1) +
      (arguments == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index == 0) return name;
    index--;
    if (typeArguments != null) {
      if (index == 0) return typeArguments!;
      index--;
    }
    if (constructorName != null) {
      if (index == 0) return constructorName!;
      index--;
    }
    return arguments!;
  }
}
