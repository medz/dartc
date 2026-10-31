part of '../nodes.dart';

/// The keyword written before a variable declaration's type or names.
enum VariableKeyword { none, varKeyword, finalKeyword, constKeyword }

/// Variable declarations sharing metadata, modifiers, and a written type.
///
/// The terminating semicolon belongs to the enclosing declaration, statement,
/// or loop.
final class VariableDeclarationList({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The written variable keyword, if any.
  final VariableKeyword keyword = .none,

  /// Whether `late` is written before the declaration.
  final bool isLate = false,

  /// The written type shared by these declarations, or `null` when omitted.
  final TypeAnnotation? type,

  required List<VariableDeclaration> declarations,
}) extends AstNode implements ForInitializer {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The declarations in source order, copied into an unmodifiable list.
  final List<VariableDeclaration> declarations = _freeze(declarations);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length + (type == null ? 0 : 1) + declarations.length;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (type != null) {
      if (index == 0) return type!;
      index--;
    }
    return declarations[index];
  }
}

/// One variable name and its optional initializer.
final class VariableDeclaration({
  required super.source,
  required super.start,
  required super.end,

  /// The declared name, including `_` when written.
  required final Identifier name,

  /// The written initializer, or `null` when absent.
  final Expression? initializer,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => initializer == null ? 1 : 2;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => name,
    1 when initializer != null => initializer!,
    _ => super.childAt(index),
  };
}

/// A declared identifier in a `for-in` header.
final class DeclaredIdentifier({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The written variable keyword, if any.
  final VariableKeyword keyword = .none,

  /// The written type, or `null` when omitted.
  final TypeAnnotation? type,

  /// The declared name.
  required final Identifier name,
}) extends AstNode implements ForInTarget {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + (type == null ? 0 : 1) + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    return type != null && index == 0 ? type! : name;
  }
}

/// A `var` or `final` pattern declaration with its initializer.
final class PatternVariableDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether the written keyword is `final` rather than `var`.
  required final bool isFinal,

  /// The written declaration pattern.
  required final DartPattern pattern,

  /// The written initializer.
  required final Expression initializer,
}) extends AstNode implements ForInitializer {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    return index == metadata.length ? pattern : initializer;
  }
}

/// A `var` or `final` pattern before `in` in a loop header.
final class PatternForInBinding({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether the written keyword is `final` rather than `var`.
  required final bool isFinal,

  /// The written declaration pattern.
  required final DartPattern pattern,
}) extends AstNode implements ForInTarget {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < metadata.length ? metadata[index] : pattern;
  }
}
