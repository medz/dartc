part of '../nodes.dart';

/// A pattern, optionally followed by a `when` guard.
sealed class CasePattern implements AstNode;

/// Pattern syntax without resolved bindings, inferred types, or match results.
sealed class DartPattern({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode implements ListPatternElement, PatternField, CasePattern;

/// A bare name whose meaning depends on its pattern context.
///
/// Analysis determines whether it denotes a constant, a declared variable,
/// or an assignment target.
final class IdentifierPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written name.
  required final Identifier name,
}) extends DartPattern {
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

/// The explicit keyword on a variable or wildcard pattern.
enum PatternVariableKeyword { none, varKeyword, finalKeyword }

/// A variable pattern with a written type, `var`, or `final`.
final class VariablePattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written keyword, if any.
  final PatternVariableKeyword keyword = .none,

  /// The written type, or `null` when omitted.
  final TypeAnnotation? type,

  /// The written variable name.
  required final Identifier name,
}) extends DartPattern {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => type == null ? 1 : 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return type != null && index == 0 ? type! : name;
  }
}

/// A wildcard `_`, with an optional written type and variable keyword.
final class WildcardPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written keyword, if any.
  final PatternVariableKeyword keyword = .none,

  /// The written type, or `null` when omitted.
  final TypeAnnotation? type,
}) extends DartPattern {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => type == null ? 0 : 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 when type != null => type!,
    _ => super.childAt(index),
  };
}

/// An expression used as a constant pattern, before constant evaluation.
final class ConstantPattern({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `const` is written before [expression].
  final bool hasConstKeyword = false,

  /// The written expression, including any parentheses.
  required final Expression expression,
}) extends DartPattern {
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

/// A parenthesized pattern, including its parentheses.
final class ParenthesizedPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern inside the parentheses.
  required final DartPattern pattern,
}) extends DartPattern {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => pattern,
    _ => super.childAt(index),
  };
}

/// A pattern followed by a `when` expression.
final class GuardedPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The pattern preceding `when`.
  required final DartPattern pattern,

  /// The written guard expression.
  required final Expression guard,
}) extends AstNode implements CasePattern {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => pattern,
    1 => guard,
    _ => super.childAt(index),
  };
}

/// A zero-width placeholder for a missing pattern.
final class MissingPattern({required super.source, required int offset})
    extends DartPattern {
  this : super(start: offset, end: offset);
}

/// A destructuring assignment written as `pattern = expression`.
final class PatternAssignmentExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written assignment pattern, before target resolution.
  required final DartPattern pattern,

  /// The expression being assigned.
  required final Expression value,
}) extends Expression {
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
