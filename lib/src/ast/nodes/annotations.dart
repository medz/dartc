part of '../nodes.dart';

/// A metadata annotation, without a resolved constant or declaration.
final class Annotation({
  required super.source,
  required super.start,
  required super.end,
  required List<Identifier> name,

  /// The explicit type arguments, or `null` when absent.
  final TypeArgumentList? typeArguments,

  /// A constructor name following explicit type arguments, or `null`.
  final Identifier? constructorName,

  /// The argument list, or `null` for a constant reference.
  final ArgumentList? arguments,
}) extends AstNode {
  /// The qualified name before type arguments, copied in source order.
  ///
  /// Resolving its components as a prefix, type, member, or constructor belongs
  /// to name binding. The list is unmodifiable.
  final List<Identifier> name = _freeze(name);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      name.length +
      (typeArguments == null ? 0 : 1) +
      (constructorName == null ? 0 : 1) +
      (arguments == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < name.length) return name[index];
    index -= name.length;
    if (typeArguments != null) {
      if (index == 0) return typeArguments!;
      index--;
    }
    if (constructorName != null) {
      if (index == 0) return constructorName!;
      index--;
    }
    return arguments!;
  }
}
