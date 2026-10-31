part of '../nodes.dart';

/// An if statement with an optional case pattern and else branch.
final class IfStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The boolean condition or expression matched by [casePattern].
  required final Expression condition,

  /// The pattern after `case` and its optional guard, or `null`.
  final CasePattern? casePattern,

  /// The statement after the condition and optional case pattern.
  required final Statement thenStatement,

  /// The written else branch, or `null` when omitted.
  final Statement? elseStatement,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      2 + (casePattern == null ? 0 : 1) + (elseStatement == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index == 0) return condition;
    index--;
    if (casePattern != null) {
      if (index == 0) return casePattern!;
      index--;
    }
    return index == 0 ? thenStatement : elseStatement!;
  }
}

/// A while statement with its condition before its body.
final class WhileStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written loop condition.
  required final Expression condition,

  /// The loop body.
  required final Statement body,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => condition,
    1 => body,
    _ => super.childAt(index),
  };
}

/// A do-while statement with its body before its condition.
final class DoStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The loop body.
  required final Statement body,

  /// The written condition after `while`.
  required final Expression condition,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => body,
    1 => condition,
    _ => super.childAt(index),
  };
}

/// A for or await-for statement.
final class ForStatement({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `await` precedes `for`.
  final bool isAwait = false,

  /// The written loop header.
  required final ForLoopParts parts,

  /// The loop body.
  required final Statement body,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => parts,
    1 => body,
    _ => super.childAt(index),
  };
}

/// A label definition, including its colon.
final class Label({
  required super.source,
  required super.start,
  required super.end,

  /// The written label name, before target resolution.
  required final Identifier name,
}) extends AstNode {
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

/// One or more labels preceding a statement.
final class LabeledStatement({
  required super.source,
  required super.start,
  required super.end,
  required List<Label> labels,

  /// The statement following the labels.
  required final Statement statement,
}) extends Statement {
  /// The labels in source order, copied into an unmodifiable list.
  final List<Label> labels = _freeze(labels);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => labels.length + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < labels.length ? labels[index] : statement;
  }
}
