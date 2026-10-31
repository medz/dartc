part of '../nodes.dart';

/// A switch expression with its cases in source order.
final class SwitchExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The expression being matched.
  required final Expression expression,

  required List<SwitchExpressionCase> cases,
}) extends Expression {
  /// The cases in source order, copied into an unmodifiable list.
  final List<SwitchExpressionCase> cases = _freeze(cases);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1 + cases.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index == 0 ? expression : cases[index - 1];
  }
}

/// A switch expression case written as `pattern => expression`.
final class SwitchExpressionCase({
  required super.source,
  required super.start,
  required super.end,

  /// The written pattern and optional guard.
  required final CasePattern pattern,

  /// The expression after `=>`.
  required final Expression value,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => pattern,
    1 => value,
    _ => super.childAt(index),
  };
}
