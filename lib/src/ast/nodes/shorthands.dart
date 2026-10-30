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

/// An explicit `const .name(...)` or `const .new(...)` shorthand head.
///
/// The constructor and constant arguments are resolved during analysis.
final class ConstDotShorthandExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written constructor name, including `new` when present.
  required final Identifier name,

  /// The constructor arguments in source order.
  required final ArgumentList arguments,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => name,
    1 => arguments,
    _ => super.childAt(index),
  };
}
