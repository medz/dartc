part of '../nodes.dart';

/// An expression, variable list, or pattern declaration initializing a loop.
sealed class ForInitializer implements AstNode;

/// An existing identifier, declared identifier, or pattern before `in`.
sealed class ForInTarget implements AstNode;

/// The syntax between a `for` header's parentheses.
sealed class ForLoopParts({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// A traditional for-loop header, including both semicolons.
///
/// Omitted conditions remain absent. The tree does not insert `true` or move
/// updates after the body; children retain their written order.
final class ForParts({
  required super.source,
  required super.start,
  required super.end,

  /// The initialization syntax, or `null` when omitted.
  final ForInitializer? initializer,

  /// The written condition, or `null` when omitted.
  final Expression? condition,

  List<Expression> updaters = const [],
}) extends ForLoopParts {
  /// The update expressions in source order, copied into an unmodifiable list.
  final List<Expression> updaters = _freeze(updaters);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      (initializer == null ? 0 : 1) +
      (condition == null ? 0 : 1) +
      updaters.length;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (initializer != null) {
      if (index == 0) return initializer!;
      index--;
    }
    if (condition != null) {
      if (index == 0) return condition!;
      index--;
    }
    return updaters[index];
  }
}

/// A for-in header with a written target and iterable expression.
final class ForInParts({
  required super.source,
  required super.start,
  required super.end,

  /// The syntax before `in`, before binding and assignment checks.
  required final ForInTarget target,

  /// The expression after `in`.
  required final Expression iterable,
}) extends ForLoopParts {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => target,
    1 => iterable,
    _ => super.childAt(index),
  };
}
