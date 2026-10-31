part of '../nodes.dart';

/// A modifier written before the `class` keyword.
enum ClassModifier {
  abstractKeyword,
  baseKeyword,
  interfaceKeyword,
  finalKeyword,
  sealedKeyword,
  mixinKeyword,
}

/// An `extends` clause with its written superclass type.
final class ExtendsClause({
  required super.source,
  required super.start,
  required super.end,

  /// The written type, before name resolution.
  required final TypeAnnotation superclass,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => superclass,
    _ => super.childAt(index),
  };
}

/// The keyword introducing a list of superclass constraints or interfaces.
enum TypeListClauseKind { withKeyword, implementsKeyword, onKeyword }

/// A `with`, `implements`, or mixin `on` clause in written order.
final class TypeListClause({
  required super.source,
  required super.start,
  required super.end,

  /// The written clause keyword.
  required final TypeListClauseKind kind,

  required List<TypeAnnotation> types,
}) extends AstNode {
  /// The written types, copied into an unmodifiable list.
  final List<TypeAnnotation> types = _freeze(types);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => types.length;
  @override
  AstNode childAt(int index) => types[index];
}

/// A class or mixin class, including an optional primary constructor header.
///
/// Members remain in source order. Declaring parameters are not expanded into
/// fields, and no implicit constructor or superclass is added.
final class ClassDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],
  List<ClassModifier> modifiers = const [],

  /// The declared class name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// Whether `const` precedes the name in a primary constructor header.
  final bool isConst = false,

  /// The primary constructor's written suffix, including `new`, or `null`.
  final Identifier? primaryConstructorName,

  /// The primary constructor parameters, or `null` when no header is written.
  final FormalParameterList? primaryParameters,

  /// The written superclass clause, or `null` when omitted.
  final ExtendsClause? extendsClause,

  /// The written mixin applications, or `null` when omitted.
  final TypeListClause? withClause,

  /// The written implemented interfaces, or `null` when omitted.
  final TypeListClause? implementsClause,

  /// Whether the declaration ends with `;` instead of a braced body.
  final bool isSemicolonBody = false,

  List<ClassMember> members = const [],
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written modifiers, including duplicates, in an unmodifiable list.
  final List<ClassModifier> modifiers = _freeze(modifiers);

  /// The written members, copied into an unmodifiable list.
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
      (extendsClause == null ? 0 : 1) +
      (withClause == null ? 0 : 1) +
      (implementsClause == null ? 0 : 1) +
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
    if (extendsClause != null) {
      if (index == 0) return extendsClause!;
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
    return members[index];
  }
}

/// A named mixin application written as `class C = B with M;`.
final class ClassTypeAliasDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],
  List<ClassModifier> modifiers = const [],

  /// The declared class name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written superclass type after `=`.
  required final TypeAnnotation superclass,

  /// The written mixin applications.
  required final TypeListClause withClause,

  /// The written implemented interfaces, or `null` when omitted.
  final TypeListClause? implementsClause,
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written modifiers, copied into an unmodifiable list.
  final List<ClassModifier> modifiers = _freeze(modifiers);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      3 +
      (typeParameters == null ? 0 : 1) +
      (implementsClause == null ? 0 : 1);
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
    if (index == 0) return superclass;
    return index == 1 ? withClause : implementsClause!;
  }
}

/// A mixin declaration with its written constraints and members.
final class MixinDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `base` precedes `mixin`.
  final bool isBase = false,

  /// The declared mixin name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written superclass constraints, or `null` when omitted.
  final TypeListClause? onClause,

  /// The written implemented interfaces, or `null` when omitted.
  final TypeListClause? implementsClause,

  /// Whether the declaration ends with `;` instead of a braced body.
  final bool isSemicolonBody = false,

  List<ClassMember> members = const [],
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written members, copied into an unmodifiable list.
  final List<ClassMember> members = _freeze(members);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      1 +
      (typeParameters == null ? 0 : 1) +
      (onClause == null ? 0 : 1) +
      (implementsClause == null ? 0 : 1) +
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
    if (onClause != null) {
      if (index == 0) return onClause!;
      index--;
    }
    if (implementsClause != null) {
      if (index == 0) return implementsClause!;
      index--;
    }
    return members[index];
  }
}
