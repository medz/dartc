part of '../nodes.dart';

/// A positional expression or a named field in a record literal.
sealed class RecordField implements AstNode;

/// A record literal with fields in their written order.
///
/// Positional fields are [Expression] nodes. Named fields can occur between
/// positional fields; their order is not normalized by this syntax tree.
final class RecordExpression({
  required super.source,
  required super.start,
  required super.end,

  /// Whether an explicit `const` precedes the literal.
  final bool hasConstKeyword = false,

  required List<RecordField> fields,
}) extends Expression {
  /// The fields in source order, copied into an unmodifiable list.
  final List<RecordField> fields = _freeze(fields);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => fields.length;
  @override
  AstNode childAt(int index) => fields[index];
}

/// A record field written as `name: expression`.
final class NamedRecordField({
  required super.source,
  required super.start,
  required super.end,

  /// The written field name.
  required final Identifier name,

  /// The expression producing the field's value.
  required final Expression value,
}) extends AstNode implements RecordField {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => name,
    1 => value,
    _ => super.childAt(index),
  };
}
