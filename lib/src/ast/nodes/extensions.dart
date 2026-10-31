part of '../nodes.dart';

/// A named or unnamed extension declaration with its written extended type.
final class ExtensionDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The written extension name, or `null` for an unnamed extension.
  final Identifier? name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written type following `on`, before resolution or inference.
  required final TypeAnnotation onType,

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
      (name == null ? 0 : 1) +
      (typeParameters == null ? 0 : 1) +
      1 +
      members.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (name != null) {
      if (index == 0) return name!;
      index--;
    }
    if (typeParameters != null) {
      if (index == 0) return typeParameters!;
      index--;
    }
    return index == 0 ? onType : members[index - 1];
  }
}

/// An extension type declaration with its written primary constructor.
///
/// The representation parameter remains in [primaryParameters], including its
/// metadata and any written modifier. No implicit `final` or field is added.
final class ExtensionTypeDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `const` is written before the primary constructor name.
  final bool isConst = false,

  /// The declared extension type name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The primary constructor's written suffix, including `new`, or `null`.
  final Identifier? primaryConstructorName,

  /// The written primary constructor parameters, including the parentheses.
  required final FormalParameterList primaryParameters,

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
      2 +
      (typeParameters == null ? 0 : 1) +
      (primaryConstructorName == null ? 0 : 1) +
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
    if (index == 0) return primaryParameters;
    index--;
    if (implementsClause != null) {
      if (index == 0) return implementsClause!;
      index--;
    }
    return members[index];
  }
}
