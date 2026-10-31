part of '../nodes.dart';

/// A subpattern or rest element in a list pattern.
sealed class ListPatternElement implements AstNode;

/// A key/pattern entry or rest element in a map pattern.
sealed class MapPatternElement implements AstNode;

/// A positional subpattern or named field in a record or object pattern.
sealed class PatternField implements AstNode;

/// A list pattern with optional explicit type arguments.
final class ListPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  required List<ListPatternElement> elements,
}) extends DartPattern {
  /// The elements in source order, copied into an unmodifiable list.
  final List<ListPatternElement> elements = _freeze(elements);

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

/// A rest element `...`, with an optional subpattern.
///
/// Permitted positions and subpatterns are checked by the parser and analyzer.
final class RestPatternElement({
  required super.source,
  required super.start,
  required super.end,

  /// The written rest subpattern, or `null` when absent.
  final DartPattern? pattern,
}) extends AstNode implements ListPatternElement, MapPatternElement {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => pattern == null ? 0 : 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 when pattern != null => pattern!,
    _ => super.childAt(index),
  };
}

/// A map pattern with entries in their written order.
final class MapPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  required List<MapPatternElement> elements,
}) extends DartPattern {
  /// The elements in source order, copied into an unmodifiable list.
  final List<MapPatternElement> elements = _freeze(elements);

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

/// A map-pattern key expression and its value pattern.
final class MapPatternEntry({
  required super.source,
  required super.start,
  required super.end,

  /// The written key, before constant evaluation.
  required final Expression key,

  /// The pattern after `:`.
  required final DartPattern value,
}) extends AstNode implements MapPatternElement {
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

/// A record pattern, including its parentheses.
final class RecordPattern({
  required super.source,
  required super.start,
  required super.end,
  required List<PatternField> fields,
}) extends DartPattern {
  /// The fields in source order, copied into an unmodifiable list.
  final List<PatternField> fields = _freeze(fields);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => fields.length;
  @override
  AstNode childAt(int index) => fields[index];
}

/// An object pattern with a written type and getter patterns.
final class ObjectPattern({
  required super.source,
  required super.start,
  required super.end,

  /// The written type name and explicit type arguments.
  required final NamedTypeAnnotation type,

  required List<PatternField> fields,
}) extends DartPattern {
  /// The fields in source order, copied into an unmodifiable list.
  final List<PatternField> fields = _freeze(fields);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1 + fields.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index == 0 ? type : fields[index - 1];
  }
}

/// A named pattern field, including its `:`.
final class NamedPatternField({
  required super.source,
  required super.start,
  required super.end,

  /// The written name, or `null` when the name is omitted for inference.
  final Identifier? name,

  /// The pattern after `:`.
  required final DartPattern pattern,
}) extends AstNode implements PatternField {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => name == null ? 1 : 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return name != null && index == 0 ? name! : pattern;
  }
}
