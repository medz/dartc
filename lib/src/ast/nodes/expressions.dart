part of '../nodes.dart';

/// An expression's syntax, without a resolved type or evaluated value.
sealed class Expression({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode implements CollectionElement, RecordField;

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

/// The lexical form of a non-string literal.
enum LiteralKind { integer, doubleLiteral, boolean, nullLiteral, symbol }

/// A literal whose original spelling is available through [text].
///
/// Numeric conversion is not performed by this node. String syntax is
/// represented by [StringExpression].
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

/// The explicit `this` receiver.
final class ThisExpression({
  required super.source,
  required super.start,
  required super.end,
}) extends Expression;

/// The explicit `super` receiver of a member access or operation.
///
/// The parser restricts its syntactic positions; analysis resolves the enclosing
/// superclass.
final class SuperExpression({
  required super.source,
  required super.start,
  required super.end,
}) extends Expression;

/// A zero-width placeholder for a missing expression.
final class MissingExpression({required super.source, required int offset})
    extends Expression {
  this : super(start: offset, end: offset);
}
