part of '../nodes.dart';

/// A block, marked block, arrow expression, or semicolon function body.
///
/// An unmodified block is represented directly by [BlockStatement].
sealed class FunctionBody implements AstNode;

/// The written modifier before a block function body.
enum FunctionBodyModifier { asyncKeyword, syncStar, asyncStar }

/// A function expression with an optional generic parameter list.
final class FunctionExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The formal parameter list.
  required final FormalParameterList parameters,

  /// The written body, without an enclosing declaration's semicolon.
  required final FunctionBody body,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => typeParameters == null ? 2 : 3;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (typeParameters != null) {
      if (index == 0) return typeParameters!;
      index--;
    }
    return index == 0 ? parameters : body;
  }
}

/// A block function body prefixed with `async`, `sync*`, or `async*`.
final class ModifiedBlockFunctionBody({
  required super.source,
  required super.start,
  required super.end,

  /// The written modifier.
  required final FunctionBodyModifier modifier,

  /// The block, including its braces.
  required final BlockStatement block,
}) extends AstNode implements FunctionBody {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => block,
    _ => super.childAt(index),
  };
}

/// An arrow function body with an optional `async` modifier.
///
/// In a declaration the range includes the terminating semicolon. In a
/// function expression it ends at the expression, without that semicolon.
final class ExpressionFunctionBody({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `async` precedes the arrow.
  final bool isAsync = false,

  /// The expression following `=>`.
  required final Expression expression,
}) extends AstNode implements FunctionBody {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => expression,
    _ => super.childAt(index),
  };
}

/// A function body written as a semicolon.
final class EmptyFunctionBody({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode implements FunctionBody;

/// A local function declaration with its metadata, signature, and body.
final class LocalFunctionDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The written return type, or `null` when omitted.
  final TypeAnnotation? returnType,

  /// The declared function name.
  required final Identifier name,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The formal parameter list.
  required final FormalParameterList parameters,

  /// The written function body.
  required final FunctionBody body,
}) extends Statement {
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
