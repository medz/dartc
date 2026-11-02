part of '../nodes.dart';

/// A logical pattern operator.
enum LogicalPatternOperator {
  and('&&'),
  or('||');

  const LogicalPatternOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// Two patterns joined by `&&` or `||`.
final class LogicalPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern before the operator.
  required final DartPattern left,

  /// The written operator.
  required final LogicalPatternOperator op,

  /// The pattern after the operator.
  required final DartPattern right,
}) extends DartPattern with _TwoChildren {
  this {
    _checkChildren(this);
  }

  @override
  AstNode get _firstChild => left;
  @override
  AstNode get _secondChild => right;
}

/// An equality or ordering operator in a relational pattern.
enum RelationalPatternOperator {
  equal('=='),
  notEqual('!='),
  less('<'),
  lessEqual('<='),
  greater('>'),
  greaterEqual('>=');

  const RelationalPatternOperator(this.spelling);

  /// The source spelling of the operator.
  final String spelling;
}

/// A relational operator followed by a constant expression.
final class RelationalPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written operator.
  required final RelationalPatternOperator op,

  /// The written operand, before constant evaluation.
  required final Expression operand,
}) extends DartPattern with _SingleChild {
  this {
    _checkChildren(this);
  }

  @override
  AstNode get _firstChild => operand;
}

/// A pattern followed by `as` and a written type.
final class CastPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern preceding `as`.
  required final DartPattern pattern,

  /// The written target type.
  required final TypeAnnotation type,
}) extends DartPattern with _TwoChildren {
  this {
    _checkChildren(this);
  }

  @override
  AstNode get _firstChild => pattern;
  @override
  AstNode get _secondChild => type;
}

/// A pattern followed by a null check `?`.
final class NullCheckPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern before `?`.
  required final DartPattern pattern,
}) extends DartPattern with _SingleChild {
  this {
    _checkChildren(this);
  }

  @override
  AstNode get _firstChild => pattern;
}

/// A pattern followed by a null assertion `!`.
final class NullAssertPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern before `!`.
  required final DartPattern pattern,
}) extends DartPattern with _SingleChild {
  this {
    _checkChildren(this);
  }

  @override
  AstNode get _firstChild => pattern;
}
