part of '../nodes.dart';

/// A top-level declaration before name binding and semantic analysis.
sealed class TopLevelDeclaration({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode implements CompilationUnitMember;

/// A zero-width declaration where recovery expected a top-level member.
final class MissingTopLevelDeclaration({
  required super.source,
  required int offset,
}) extends TopLevelDeclaration {
  this : super(start: offset, end: offset);
}

/// A top-level function with its written signature and body.
final class TopLevelFunctionDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The written formal parameter list.
  required final FormalParameterList parameters,

  /// The written function body, including any terminating semicolon.
  required final FunctionBody body,
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
      3;
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
    if (typeParameters != null) {
      if (index == 0) return typeParameters!;
      index--;
    }
    return index == 0 ? parameters : body;
  }
}

/// A top-level getter with its written signature and body.
final class TopLevelGetterDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared name.
  required final Identifier name,

  /// The written function body, including any terminating semicolon.
  required final FunctionBody body,
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + (returnType == null ? 0 : 1) + 2;
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
    return body;
  }
}

/// A top-level setter with its written signature and body.
final class TopLevelSetterDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared name.
  required final Identifier name,

  /// The written formal parameter list.
  required final FormalParameterList parameters,

  /// The written function body, including any terminating semicolon.
  required final FunctionBody body,
}) extends TopLevelDeclaration {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + (returnType == null ? 0 : 1) + 3;
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
    return index == 0 ? parameters : body;
  }
}

/// A top-level variable declaration with its terminating semicolon.
final class TopLevelVariableDeclaration({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// The variables, including their metadata and excluding the semicolon.
  required final VariableDeclarationList variables,
}) extends TopLevelDeclaration {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => variables,
    _ => super.childAt(index),
  };
}
