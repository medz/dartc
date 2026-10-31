part of '../nodes.dart';

/// A library directive and its written metadata.
sealed class Directive({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],
}) extends AstNode implements CompilationUnitMember {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);
}

/// A dotted library name or string URI following `part of`.
sealed class PartOfTarget implements AstNode;

/// Identifiers joined by dots, without name resolution.
final class DottedName({
  required super.source,
  required super.start,
  required super.end,
  required List<Identifier> components,
}) extends AstNode implements PartOfTarget {
  /// The written components, copied into an unmodifiable list.
  final List<Identifier> components = _freeze(components);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => components.length;
  @override
  AstNode childAt(int index) => components[index];
}

/// A named or unnamed library directive, including its semicolon.
final class LibraryDirective({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,

  /// The written name, or `null` for `library;`.
  final DottedName? name,
}) extends Directive {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + (name == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < metadata.length ? metadata[index] : name!;
  }
}

/// A part directive, including its semicolon.
final class PartDirective({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,

  /// The written URI string, before decoding or resolution.
  required final StringExpression uri,
}) extends Directive {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < metadata.length ? metadata[index] : uri;
  }
}

/// A part-of directive, including its semicolon.
final class PartOfDirective({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,

  /// The written library name or URI, before resolution.
  required final PartOfTarget target,
}) extends Directive {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < metadata.length ? metadata[index] : target;
  }
}

/// A conditional URI written as `if (name == value) uri` or `if (name) uri`.
final class ConditionalUri({
  required super.source,
  required super.start,
  required super.end,

  /// The written environment declaration name.
  required final DottedName name,

  /// The string following `==`, or `null` when the comparison is omitted.
  final StringExpression? value,

  /// The written alternative URI string.
  required final StringExpression uri,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => value == null ? 2 : 3;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index == 0) return name;
    return value != null && index == 1 ? value! : uri;
  }
}

/// The keyword introducing a namespace combinator.
enum NamespaceCombinatorKind { show, hide }

/// A show or hide clause with its names in written order.
final class NamespaceCombinator({
  required super.source,
  required super.start,
  required super.end,

  /// The written combinator keyword.
  required final NamespaceCombinatorKind kind,

  required List<Identifier> names,
}) extends AstNode {
  /// The written names, including duplicates, copied into an unmodifiable list.
  final List<Identifier> names = _freeze(names);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => names.length;
  @override
  AstNode childAt(int index) => names[index];
}

/// An import directive with its conditional URIs, prefix, and combinators.
final class ImportDirective({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,

  /// The written default URI string, before decoding or resolution.
  required final StringExpression uri,

  List<ConditionalUri> configurations = const [],

  /// Whether `deferred` is written on the import.
  final bool isDeferred = false,

  /// The written import prefix, or `null` when omitted.
  final Identifier? prefix,

  List<NamespaceCombinator> combinators = const [],
}) extends Directive {
  /// The alternatives in source order, copied into an unmodifiable list.
  final List<ConditionalUri> configurations = _freeze(configurations);

  /// The combinators in source order, copied into an unmodifiable list.
  final List<NamespaceCombinator> combinators = _freeze(combinators);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      1 +
      configurations.length +
      (prefix == null ? 0 : 1) +
      combinators.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index == 0) return uri;
    index--;
    if (index < configurations.length) return configurations[index];
    index -= configurations.length;
    if (prefix != null) {
      if (index == 0) return prefix!;
      index--;
    }
    return combinators[index];
  }
}

/// An export directive with its conditional URIs and combinators.
final class ExportDirective({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,

  /// The written default URI string, before decoding or resolution.
  required final StringExpression uri,

  List<ConditionalUri> configurations = const [],
  List<NamespaceCombinator> combinators = const [],
}) extends Directive {
  /// The alternatives in source order, copied into an unmodifiable list.
  final List<ConditionalUri> configurations = _freeze(configurations);

  /// The combinators in source order, copied into an unmodifiable list.
  final List<NamespaceCombinator> combinators = _freeze(combinators);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length + 1 + configurations.length + combinators.length;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index == 0) return uri;
    index--;
    if (index < configurations.length) return configurations[index];
    return combinators[index - configurations.length];
  }
}
