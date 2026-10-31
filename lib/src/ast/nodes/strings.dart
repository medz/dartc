part of '../nodes.dart';

/// A string expression, including interpolation or adjacent literals.
sealed class StringExpression({
  required super.source,
  required super.start,
  required super.end,
}) extends Expression implements PartOfTarget;

/// A zero-width string where recovery expected a literal.
final class MissingStringExpression({
  required super.source,
  required int offset,
}) extends StringExpression {
  this : super(start: offset, end: offset);
}

/// One non-interpolated string literal, including its prefix and delimiters.
///
/// Raw strings, escape sequences, line endings, and multiline delimiters remain
/// unchanged in [text]. The decoded string value is determined during analysis.
final class StringLiteralExpression({
  required super.source,
  required super.start,
  required super.end,
}) extends StringExpression;

/// One string literal containing interpolated expressions.
final class InterpolatedStringExpression({
  required super.source,
  required super.start,
  required super.end,
  required List<StringPart> parts,
}) extends StringExpression {
  /// The text and interpolations in source order, copied into an immutable list.
  final List<StringPart> parts = _freeze(parts);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => parts.length;
  @override
  AstNode childAt(int index) => parts[index];
}

/// String literals joined by adjacency, including intervening trivia.
final class AdjacentStringsExpression({
  required super.source,
  required super.start,
  required super.end,
  required List<StringExpression> strings,
}) extends StringExpression {
  /// The strings in source order, copied into an unmodifiable list.
  final List<StringExpression> strings = _freeze(strings);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => strings.length;
  @override
  AstNode childAt(int index) => strings[index];
}

/// A text segment or interpolation within one string literal.
sealed class StringPart({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// An unchanged text segment between interpolations.
///
/// The first and last segments include the literal's opening and closing
/// delimiters. A segment between adjacent interpolations can be empty.
/// Escape decoding and multiline whitespace processing belong to analysis.
final class StringText({
  required super.source,
  required super.start,
  required super.end,
}) extends StringPart;

/// A string interpolation, including its `$` and any braces.
final class StringInterpolation({
  required super.source,
  required super.start,
  required super.end,

  /// The embedded expression, identifier, or `this` reference.
  required final Expression expression,

  /// Whether the interpolation uses `${...}` rather than `$name` or `$this`.
  required final bool isBraced,
}) extends StringPart {
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
