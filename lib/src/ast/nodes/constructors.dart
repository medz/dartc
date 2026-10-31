part of '../nodes.dart';

/// A function body or factory redirection written after a constructor header.
sealed class ConstructorBody implements AstNode;

/// The written keyword introducing a constructor, apart from `const`.
enum ConstructorKeyword { none, newKeyword, factoryKeyword }

/// A constructor declaration within a class body.
///
/// Written names and keywords are retained without expanding abbreviated
/// constructors or binding redirection targets.
final class ConstructorDeclaration({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// Whether `external` is written on the declaration.
  final bool isExternal = false,

  /// Whether `const` is written on the declaration.
  final bool isConst = false,

  /// The written `new` or `factory` keyword, if any.
  final ConstructorKeyword keyword = .none,

  List<Identifier> name = const [],

  /// The written formal parameter list.
  required final FormalParameterList parameters,

  List<ConstructorInitializer> initializers = const [],

  /// The written function body or factory redirection, including its semicolon.
  required final ConstructorBody body,
}) extends ClassMember {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written names before the parameters, in an unmodifiable list.
  ///
  /// Examples are `[C, named]` for `C.named()`, `[named]` for `new named()`,
  /// and an empty list for `new()`. A single name after `factory` is retained
  /// without deciding whether it repeats the enclosing class name.
  final List<Identifier> name = _freeze(name);

  /// The written initializers in order, copied into an unmodifiable list.
  final List<ConstructorInitializer> initializers = _freeze(initializers);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + name.length + initializers.length + 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (index < name.length) return name[index];
    index -= name.length;
    if (index == 0) return parameters;
    index--;
    return index < initializers.length ? initializers[index] : body;
  }
}

/// The `this` initialization and body part of a primary constructor.
///
/// This member occurs at its written location, separately from the parameters
/// in the declaration header. It has no back-reference to that header.
final class PrimaryConstructorBody({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],
  List<ConstructorInitializer> initializers = const [],

  /// The written body, including any terminating semicolon.
  required final FunctionBody body,
}) extends ClassMember {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written initializers in order, copied into an unmodifiable list.
  final List<ConstructorInitializer> initializers = _freeze(initializers);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + initializers.length + 1;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    return index < initializers.length ? initializers[index] : body;
  }
}

/// A factory redirection from `=` through the terminating semicolon.
final class FactoryRedirectBody({
  required super.source,
  required super.start,
  required super.end,
  required List<Identifier> name,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,

  /// A constructor name following explicit type arguments, or `null`.
  final Identifier? constructorName,
}) extends AstNode implements ConstructorBody {
  /// The qualified name before type arguments, copied in source order.
  ///
  /// Components remain unresolved, as in `p.C.named`; the list is unmodifiable.
  final List<Identifier> name = _freeze(name);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      name.length +
      (typeArguments == null ? 0 : 1) +
      (constructorName == null ? 0 : 1);
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < name.length) return name[index];
    index -= name.length;
    return typeArguments != null && index == 0
        ? typeArguments!
        : constructorName!;
  }
}

/// A written entry in a constructor initializer list.
sealed class ConstructorInitializer({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode;

/// A field initializer written as `name = value` or `this.name = value`.
final class FieldInitializer({
  required super.source,
  required super.start,
  required super.end,

  /// Whether `this.` precedes the field name.
  final bool hasThis = false,

  /// The written field name, before binding.
  required final Identifier name,

  /// The written initializer expression.
  required final Expression value,
}) extends ConstructorInitializer {
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

/// An assertion in a constructor initializer list, without a semicolon.
final class AssertInitializer({
  required super.source,
  required super.start,
  required super.end,

  /// The written condition.
  required final Expression condition,

  /// The written message, or `null` when omitted.
  final Expression? message,
}) extends ConstructorInitializer {
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

/// An explicit invocation of a superclass constructor in an initializer list.
final class SuperConstructorInitializer({
  required super.source,
  required super.start,
  required super.end,

  /// The written constructor suffix, or `null` when omitted.
  final Identifier? name,

  /// The written constructor arguments.
  required final ArgumentList arguments,
}) extends ConstructorInitializer {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => name == null ? 1 : 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return name != null && index == 0 ? name! : arguments;
  }
}

/// A generative redirection written as `this(...)` or `this.name(...)`.
final class RedirectingConstructorInitializer({
  required super.source,
  required super.start,
  required super.end,

  /// The written constructor suffix, or `null` when omitted.
  final Identifier? name,

  /// The written constructor arguments.
  required final ArgumentList arguments,
}) extends ConstructorInitializer {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => name == null ? 1 : 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return name != null && index == 0 ? name! : arguments;
  }
}
