part of '../nodes.dart';

/// An expression's syntax, without a resolved type or evaluated value.
sealed class Expression({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// A reference written as one identifier.
final class IdentifierExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The referenced name.
  required final Identifier identifier,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => identifier,
    _ => super.childAt(index),
  };
}

/// The lexical form of a non-interpolated literal.
enum LiteralKind {
  integer,
  doubleLiteral,
  boolean,
  nullLiteral,
  string,
  symbol,
}

/// A literal whose original spelling is available through [text].
///
/// Numeric conversion and string-escape decoding are not performed by this
/// node. Interpolated strings require a structured interpolation node.
final class LiteralExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The literal's lexical form.
  required final LiteralKind kind,
}) extends Expression;

/// A parenthesized expression, including its parentheses.
final class ParenthesizedExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression inside the parentheses.
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

/// A prefix operator that does not assign to its operand.
enum UnaryOperator {
  negate('-'),
  logicalNot('!'),
  bitwiseNot('~');

  const UnaryOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// A prefix operation on an expression.
final class UnaryExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written operator.
  required final UnaryOperator op,

  /// The operand expression.
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

/// A binary operator whose two operands are expressions.
enum BinaryOperator {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('/'),
  truncateDivide('~/'),
  remainder('%'),
  shiftLeft('<<'),
  shiftRight('>>'),
  unsignedShiftRight('>>>'),
  bitwiseAnd('&'),
  bitwiseOr('|'),
  bitwiseXor('^'),
  less('<'),
  lessEqual('<='),
  greater('>'),
  greaterEqual('>='),
  equal('=='),
  notEqual('!='),
  logicalAnd('&&'),
  logicalOr('||'),
  ifNull('??');

  const BinaryOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// A binary expression, preserving the written operand order.
final class BinaryExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The left operand.
  required final Expression left,

  /// The written operator.
  required final BinaryOperator op,

  /// The right operand.
  required final Expression right,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => left,
    1 => right,
    _ => super.childAt(index),
  };
}

/// A conditional expression written with `?` and `:`.
final class ConditionalExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The condition expression.
  required final Expression condition,

  /// The expression selected by a true condition.
  required final Expression thenExpression,

  /// The expression selected by a false condition.
  required final Expression elseExpression,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 3;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => condition,
    1 => thenExpression,
    2 => elseExpression,
    _ => super.childAt(index),
  };
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
