part of '../nodes.dart';

/// A member written inside a class, mixin, enum, or extension declaration.
sealed class ClassMember({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// A field declaration with its written modifiers and terminating semicolon.
final class FieldDeclaration({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `static` is written on the declaration.
  final bool isStatic = false,

  /// Whether `abstract` is written on the declaration.
  final bool isAbstract = false,

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `covariant` is written on the declaration.
  final bool isCovariant = false,

  /// The variables, including their metadata and excluding the semicolon.
  required final VariableDeclarationList variables,
}) extends ClassMember {
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

/// An operator symbol that can be declared by a Dart class.
///
/// Unary and binary `-` share a spelling; their formal parameters distinguish
/// the declarations.
enum DeclaredOperator {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('/'),
  truncateDivide('~/'),
  remainder('%'),
  lessThan('<'),
  lessThanOrEqual('<='),
  greaterThan('>'),
  greaterThanOrEqual('>='),
  equal('=='),
  shiftLeft('<<'),
  shiftRight('>>'),
  unsignedShiftRight('>>>'),
  bitwiseAnd('&'),
  bitwiseOr('|'),
  bitwiseXor('^'),
  bitwiseNot('~'),
  indexRead('[]'),
  indexAssign('[]=');

  const DeclaredOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// An operator declaration with its written return type, parameters, and body.
final class OperatorDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `static` is written on the declaration, before legality checks.
  final bool isStatic = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The written operator symbol.
  required final DeclaredOperator op,

  /// The written formal parameter list.
  required final FormalParameterList parameters,

  /// The written body, including any terminating semicolon.
  required final FunctionBody body,
}) extends ClassMember {
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
    return index == 0 ? parameters : body;
  }
}

/// A method with its written signature and body.
final class MethodDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `static` is written on the declaration.
  final bool isStatic = false,

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
}) extends ClassMember {
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

/// A getter with its written signature and body.
final class GetterDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `static` is written on the declaration.
  final bool isStatic = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared name.
  required final Identifier name,

  /// The written function body, including any terminating semicolon.
  required final FunctionBody body,
}) extends ClassMember {
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

/// A setter with its written signature and body.
final class SetterDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `static` is written on the declaration.
  final bool isStatic = false,

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared name.
  required final Identifier name,

  /// The written formal parameter list.
  required final FormalParameterList parameters,

  /// The written function body, including any terminating semicolon.
  required final FunctionBody body,
}) extends ClassMember {
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
