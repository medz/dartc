part of '../nodes.dart';

/// A simple, compound, or null-coalescing assignment operator.
enum AssignmentOperator {
  assign('='),
  multiply('*='),
  divide('/='),
  truncateDivide('~/='),
  remainder('%='),
  add('+='),
  subtract('-='),
  shiftLeft('<<='),
  shiftRight('>>='),
  unsignedShiftRight('>>>='),
  bitwiseAnd('&='),
  bitwiseXor('^='),
  bitwiseOr('|='),
  ifNull('??=');

  const AssignmentOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// An assignment that retains its written target and right operand once.
///
/// Parsing checks the form of [left]; analysis resolves its read and write
/// targets. A compound assignment is not expanded into separate syntax reads
/// and writes.
final class AssignmentExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written assignment target.
  required final Expression left,

  /// The written assignment operator.
  required final AssignmentOperator op,

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

/// An increment or decrement operator.
enum UpdateOperator {
  increment('++'),
  decrement('--');

  const UpdateOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// A prefix or postfix increment or decrement.
final class UpdateExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written assignment target, occurring once in this syntax tree.
  required final Expression operand,

  /// The written update operator.
  required final UpdateOperator op,

  /// Whether the operator precedes the operand.
  required final bool isPrefix,
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

/// An explicit type conversion written with `as`.
final class CastExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression before `as`.
  required final Expression expression,

  /// The written target type.
  required final TypeAnnotation type,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => expression,
    1 => type,
    _ => super.childAt(index),
  };
}

/// A type test written with `is` or `is!`.
final class TypeTestExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression being tested.
  required final Expression expression,

  /// The written type used by the test.
  required final TypeAnnotation type,

  /// Whether the test uses `is!`.
  final bool isNegated = false,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => expression,
    1 => type,
    _ => super.childAt(index),
  };
}

/// An expression preceded by `await`.
final class AwaitExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The operand of `await`.
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

/// An expression preceded by `throw`.
final class ThrowExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression producing the thrown object.
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
