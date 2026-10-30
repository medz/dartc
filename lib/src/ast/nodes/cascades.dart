part of '../nodes.dart';

/// A cascade with one receiver and its sections in source order.
///
/// Each section starts with a [CascadePropertyExpression] or
/// [CascadeIndexExpression], possibly inside calls, selectors, or an assignment.
/// Sections refer to this receiver without containing another copy of it.
final class CascadeExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression producing the cascade receiver.
  required final Expression target,

  /// Whether the first section starts with `?..`.
  final bool isNullAware = false,

  required List<Expression> sections,
}) extends Expression {
  /// The sections in source order, copied into an unmodifiable list.
  final List<Expression> sections = _freeze(sections);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1 + sections.length;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index == 0 ? target : sections[index - 1];
  }
}

/// The first property selector of a cascade section, including `..` or `?..`.
final class CascadePropertyExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The name selected on the enclosing cascade's receiver.
  required final Identifier property,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => property,
    _ => super.childAt(index),
  };
}

/// The first index selector of a cascade section, including `..` or `?..`.
final class CascadeIndexExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The index expression applied to the enclosing cascade's receiver.
  required final Expression index,
}) extends Expression {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => this.index,
    _ => super.childAt(index),
  };
}
