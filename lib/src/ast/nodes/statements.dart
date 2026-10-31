part of '../nodes.dart';

/// A statement's syntax before control-flow and semantic analysis.
sealed class Statement({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// A block of statements, including its braces.
///
/// Also represents an unmodified synchronous function body.
final class BlockStatement({
  required super.source,
  required super.start,
  required super.end,
  required List<Statement> statements,
}) extends Statement implements FunctionBody {
  /// The statements in source order, copied into an unmodifiable list.
  final List<Statement> statements = _freeze(statements);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => statements.length;
  @override
  AstNode childAt(int index) => statements[index];
}

/// An empty statement written as a semicolon.
final class EmptyStatement({
  required super.source,
  required super.start,
  required super.end,
}) extends Statement;

/// A zero-width placeholder for a missing statement.
final class MissingStatement({required super.source, required int offset})
    extends Statement {
  this : super(start: offset, end: offset);
}

/// An expression statement, including its terminating semicolon.
final class ExpressionStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written expression.
  required final Expression expression,
}) extends Statement {
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

/// A variable declaration list with its terminating semicolon.
final class VariableDeclarationStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The variable declaration list, excluding the semicolon.
  required final VariableDeclarationList variables,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => variables,
    _ => super.childAt(index),
  };
}

/// A pattern variable declaration with its terminating semicolon.
final class PatternVariableDeclarationStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern declaration, excluding the semicolon.
  required final PatternVariableDeclaration declaration,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => declaration,
    _ => super.childAt(index),
  };
}

/// A `break` statement with an optional label.
final class BreakStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written label, or `null` when omitted.
  final Identifier? label,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => label == null ? 0 : 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 when label != null => label!,
    _ => super.childAt(index),
  };
}

/// A `continue` statement with an optional label.
final class ContinueStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written label, or `null` when omitted.
  final Identifier? label,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => label == null ? 0 : 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 when label != null => label!,
    _ => super.childAt(index),
  };
}

/// A `return` statement with an optional expression.
final class ReturnStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written expression, or `null` when omitted.
  final Expression? expression,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => expression == null ? 0 : 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 when expression != null => expression!,
    _ => super.childAt(index),
  };
}

/// A `yield` or `yield*` statement.
final class YieldStatement({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `*` follows `yield`.
  final bool isStar = false,

  /// The written yielded expression.
  required final Expression expression,
}) extends Statement {
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

/// An assert statement with an optional message.
final class AssertStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The written condition.
  required final Expression condition,

  /// The written message, or `null` when omitted.
  final Expression? message,
}) extends Statement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => message == null ? 1 : 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => condition,
    1 when message != null => message!,
    _ => super.childAt(index),
  };
}
