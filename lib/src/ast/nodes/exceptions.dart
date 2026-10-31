part of '../nodes.dart';

/// A rethrow statement, including its semicolon.
final class RethrowStatement({
  required super.source,
  required super.start,
  required super.end,
}) extends Statement;

/// A try statement with ordered catch clauses and an optional finally block.
final class TryStatement({
  required super.source,
  required super.start,
  required super.end,

  /// The block following `try`.
  required final BlockStatement body,

  List<CatchClause> catchClauses = const [],

  /// The written finally block, or `null` when omitted.
  final BlockStatement? finallyBlock,
}) extends Statement {
  /// The catch clauses in source order, copied into an unmodifiable list.
  final List<CatchClause> catchClauses = _freeze(catchClauses);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      1 + catchClauses.length + (finallyBlock == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index == 0) return body;
    index--;
    return index < catchClauses.length ? catchClauses[index] : finallyBlock!;
  }
}

/// An `on`, `catch`, or `on`-`catch` clause with its block.
///
/// Omitted exception types and parameters remain absent; no catch-all type or
/// implicit parameter is inserted.
final class CatchClause({
  required super.source,
  required super.start,
  required super.end,

  /// The type following `on`, or `null` when omitted.
  final TypeAnnotation? exceptionType,

  /// The first catch parameter, or `null` when no catch parameters are written.
  final Identifier? exceptionParameter,

  /// The second catch parameter, or `null` when omitted.
  final Identifier? stackTraceParameter,

  /// The clause's block.
  required final BlockStatement body,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      (exceptionType == null ? 0 : 1) +
      (exceptionParameter == null ? 0 : 1) +
      (stackTraceParameter == null ? 0 : 1) +
      1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (exceptionType != null) {
      if (index == 0) return exceptionType!;
      index--;
    }
    if (exceptionParameter != null) {
      if (index == 0) return exceptionParameter!;
      index--;
    }
    if (stackTraceParameter != null) {
      if (index == 0) return stackTraceParameter!;
      index--;
    }
    return body;
  }
}
