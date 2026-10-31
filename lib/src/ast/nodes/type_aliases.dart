part of '../nodes.dart';

/// A type alias written as `typedef Name<T> = Type;`.
final class TypeAliasDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The declared alias name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written aliased type, before resolution or expansion.
  required final TypeAnnotation type,
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 2 + (typeParameters == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index == 0) return name;
    index--;
    return typeParameters != null && index == 0 ? typeParameters! : type;
  }
}

/// A type alias written with the legacy function declaration syntax.
final class FunctionTypeAliasDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared alias name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written formal parameters, without inferred types.
  required final FormalParameterList parameters,
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      (returnType == null ? 0 : 1) +
      (typeParameters == null ? 0 : 1) +
      2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (returnType != null) {
      if (index == 0) return returnType!;
      index--;
    }
    if (index == 0) return name;
    index--;
    return typeParameters != null && index == 0 ? typeParameters! : parameters;
  }
}
