part of '../nodes.dart';

/// A switch statement with its members in source order.
final class SwitchStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The expression being matched.
  required final Expression expression,

  required List<SwitchStatementMember> members,
}) extends Statement {
  /// The case and default members, copied into an unmodifiable list.
  final List<SwitchStatementMember> members = _freeze(members);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1 + members.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index == 0 ? expression : members[index - 1];
  }
}

/// A case or default member and its written statements.
///
/// Empty members remain separate, preserving labels and consecutive cases.
/// Shared bindings, label targets, and completion rules require analysis.
final class SwitchStatementMember({
  required super.source,
  required super.start,
  required super.end,
  List<Label> labels = const [],

  /// The case pattern and optional guard, or `null` for a default member.
  final CasePattern? pattern,

  required List<Statement> statements,
}) extends AstNode {
  /// The leading labels in source order, copied into an unmodifiable list.
  final List<Label> labels = _freeze(labels);

  /// The statements in source order, copied into an unmodifiable list.
  final List<Statement> statements = _freeze(statements);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      labels.length + (pattern == null ? 0 : 1) + statements.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < labels.length) return labels[index];
    index -= labels.length;
    if (pattern != null) {
      if (index == 0) return pattern!;
      index--;
    }
    return statements[index];
  }
}

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
