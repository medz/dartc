part of '../nodes.dart';

/// An index access through `[]` or `?[]`.
final class IndexExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The receiver expression, occurring once in this syntax tree.
  required final Expression target,

  /// The written index expression.
  required final Expression index,

  /// Whether the access uses `?[]`.
  final bool isNullAware = false,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => target,
    1 => this.index,
    _ => super.childAt(index),
  };
}

/// A postfix null assertion, including its `!`.
final class NullAssertionExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression before `!`.
  required final Expression operand,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => operand,
    _ => super.childAt(index),
  };
}

/// Explicit type arguments following an expression without call arguments.
///
/// This represents forms such as `f<int>` and `C<int>`. Whether the result is
/// a function value, type literal, or part of a constructor reference is
/// determined during analysis.
final class TypeInstantiationExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression before the type arguments.
  required final Expression expression,

  /// The explicit type arguments.
  required final TypeArgumentList typeArguments,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => expression,
    1 => typeArguments,
    _ => super.childAt(index),
  };
}

/// An explicit property access through `.` or `?.`.
final class PropertyAccessExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The receiver expression.
  required final Expression target,

  /// The property name.
  required final Identifier property,

  /// Whether the access uses `?.`.
  final bool isNullAware = false,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => target,
    1 => property,
    _ => super.childAt(index),
  };
}

/// A call with optional explicit type arguments.
final class InvocationExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression being called.
  required final Expression callee,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  /// The arguments in their written evaluation order.
  required final ArgumentList arguments,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => typeArguments == null ? 2 : 3;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index == 0) return callee;
    return typeArguments != null && index == 1 ? typeArguments! : arguments;
  }
}

/// The explicit keyword, if any, on an instance creation expression.
enum InstanceCreationKind { implicit, newKeyword, constKeyword }

/// An instance creation with an unresolved qualified name.
final class InstanceCreationExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The explicit keyword, or [InstanceCreationKind.implicit] when omitted.
  final InstanceCreationKind kind = .implicit,

  required List<Identifier> name,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  /// A constructor name following explicit type arguments, or `null`.
  final Identifier? constructorName,

  /// The constructor arguments.
  required final ArgumentList arguments,
}) extends Expression {
  /// The qualified name before type arguments, copied in source order.
  ///
  /// Without type arguments, `A.b` can name a prefixed type or a named
  /// constructor. Binding determines the meaning of these components.
  final List<Identifier> name = _freeze(name);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      name.length +
      (typeArguments == null ? 0 : 1) +
      (constructorName == null ? 0 : 1) +
      1;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < name.length) return name[index];
    index -= name.length;
    if (typeArguments != null) {
      if (index == 0) return typeArguments!;
      index--;
    }
    if (constructorName != null && index == 0) return constructorName!;
    return arguments;
  }
}

/// Arguments to a call or annotation, including their parentheses.
final class ArgumentList({
  required super.source,
  required super.start,
  required super.end,
  required List<Argument> arguments,
}) extends AstNode {
  /// The arguments in evaluation order, copied into an unmodifiable list.
  final List<Argument> arguments = _freeze(arguments);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => arguments.length;
  @override
  AstNode childAt(int index) => arguments[index];
}

/// A positional or named argument.
final class Argument({
  required super.source,
  required super.start,
  required super.end,

  /// The label before `:`, or `null` for a positional argument.
  final Identifier? name,

  /// The argument's expression.
  required final Expression value,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => name == null ? 1 : 2;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return name != null && index == 0 ? name! : value;
  }
}
