part of '../nodes.dart';

/// An expression, entry, spread, or control-flow element of a collection.
sealed class CollectionElement implements AstNode;

/// The delimiters of a collection literal, before type inference.
enum CollectionLiteralKind {
  /// A list literal delimited by `[` and `]`.
  list,

  /// A literal delimited by `{` and `}`, whose set or map type is unresolved.
  setOrMap,
}

/// A list or brace-delimited collection literal.
///
/// Ordinary expression elements are [Expression] nodes. Set/map classification,
/// implicit const contexts, and element types are determined during analysis.
final class CollectionExpression({
  required super.source,
  required super.start,
  required super.end,

  /// The written collection form.
  required final CollectionLiteralKind kind,

  /// Whether an explicit `const` precedes the literal.
  final bool hasConstKeyword = false,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  required List<CollectionElement> elements,
}) extends Expression {
  /// The elements in source order, copied into an unmodifiable list.
  final List<CollectionElement> elements = _freeze(elements);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => elements.length + (typeArguments == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (typeArguments != null) {
      if (index == 0) return typeArguments!;
      index--;
    }
    return elements[index];
  }
}

/// A collection element written as `?expression`.
final class NullAwareElement({
  required super.source,
  required super.start,
  required super.end,

  /// The expression whose non-null result is inserted.
  required final Expression expression,
}) extends AstNode implements CollectionElement {
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

/// A map entry with optional null-aware markers on its key and value.
final class MapEntryElement({
  required super.source,
  required super.start,
  required super.end,

  /// The expression before `:`.
  required final Expression key,

  /// The expression after `:`.
  required final Expression value,

  /// Whether `?` precedes the key expression.
  final bool isNullAwareKey = false,

  /// Whether `?` precedes the value expression.
  final bool isNullAwareValue = false,
}) extends AstNode implements CollectionElement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => key,
    1 => value,
    _ => super.childAt(index),
  };
}

/// A spread written as `...expression` or `...?expression`.
final class SpreadElement({
  required super.source,
  required super.start,
  required super.end,

  /// The expression producing the collection to spread.
  required final Expression expression,

  /// Whether the spread uses `...?`.
  final bool isNullAware = false,
}) extends AstNode implements CollectionElement {
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

/// A conditional collection element, with an optional `else` element.
final class IfElement({
  required super.source,
  required super.start,
  required super.end,

  /// The boolean condition expression.
  required final Expression condition,

  /// The element selected when the condition is true.
  required final CollectionElement thenElement,

  /// The element selected when the condition is false, or `null` when absent.
  final CollectionElement? elseElement,
}) extends AstNode implements CollectionElement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => elseElement == null ? 2 : 3;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => condition,
    1 => thenElement,
    2 when elseElement != null => elseElement!,
    _ => super.childAt(index),
  };
}
