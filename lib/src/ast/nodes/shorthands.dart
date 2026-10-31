part of '../nodes.dart';

/// A dot shorthand and its entire following selector chain.
///
/// The chain starts with a [DotShorthandReferenceExpression] or
/// [ConstDotShorthandExpression]. This boundary identifies the expression whose
/// context supplies the leading member's namespace during type inference.
final class DotShorthandExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The shorthand head and any following selectors.
  required final Expression expression,
}) extends Expression {
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

/// A leading `.name` or `.new` in a dot shorthand.
final class DotShorthandReferenceExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written name, including `new` for an unnamed constructor reference.
  required final Identifier name,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => name,
    _ => super.childAt(index),
  };
}

/// A shorthand head with an explicit `const` prefix.
///
/// The referenced member or constructor and constant arguments are resolved
/// during analysis. An omitted argument list is retained as a reference.
final class ConstDotShorthandExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written member or constructor name, including `new` when present.
  required final Identifier name,

  /// Explicit type arguments, retained for later constructor checks.
  final TypeArgumentList? typeArguments,

  /// The written constructor arguments, or `null` for a reference.
  final ArgumentList? arguments,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      1 + (typeArguments == null ? 0 : 1) + (arguments == null ? 0 : 1);
  @override
  AstNode childAt(int index) => switch (index) {
    0 => name,
    1 when typeArguments != null || arguments != null =>
      typeArguments ?? arguments!,
    2 when typeArguments != null && arguments != null => arguments!,
    _ => super.childAt(index),
  };
}
