part of '../nodes.dart';

/// The position and optionality of a declared formal parameter.
enum FormalParameterKind {
  requiredPositional,
  optionalPositional,
  optionalNamed,
  requiredNamed,
}

/// The written receiver prefix on a formal parameter's name.
enum ParameterPrefix { none, thisKeyword, superKeyword }

/// The separator before a parameter's default expression.
enum ParameterDefaultSeparator { equals, colon }

/// Declared formal parameters, including their parentheses.
final class FormalParameterList({
  required super.source,
  required super.start,
  required super.end,
  required List<FormalParameter> parameters,
}) extends AstNode {
  /// The parameters in source order, copied into an unmodifiable list.
  final List<FormalParameter> parameters = _freeze(parameters);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => parameters.length;
  @override
  AstNode childAt(int index) => parameters[index];
}

/// A formal parameter with its written modifiers, type, name, and default.
///
/// For a function-form parameter, [type] is the written return type and
/// [functionSuffix] follows the name. Parameter legality and field or super
/// binding are checked by the parser and analyzer.
final class FormalParameter({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The parameter's position and optionality.
  required final FormalParameterKind kind,

  /// The written `this.` or `super.` prefix, if any.
  final ParameterPrefix prefix = .none,

  /// The written `var`, `final`, or `const` keyword, if any.
  final VariableKeyword keyword = .none,

  /// Whether `covariant` is written on the parameter.
  final bool isCovariant = false,

  /// The written type, or `null` when omitted.
  final TypeAnnotation? type,

  /// The declared name, including `_` when written.
  required final Identifier name,

  /// The function-form suffix after the name, or `null` when absent.
  final FunctionParameterSuffix? functionSuffix,

  /// The default expression and its separator, or `null` when absent.
  final ParameterDefault? defaultClause,
}) extends AstNode {
  /// The metadata in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      metadata.length +
      (type == null ? 0 : 1) +
      1 +
      (functionSuffix == null ? 0 : 1) +
      (defaultClause == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    index -= metadata.length;
    if (type != null) {
      if (index == 0) return type!;
      index--;
    }
    if (index == 0) return name;
    index--;
    if (functionSuffix != null) {
      if (index == 0) return functionSuffix!;
      index--;
    }
    return defaultClause!;
  }
}

/// The type parameters, parameters, and nullable marker after a formal's name.
final class FunctionParameterSuffix({
  required super.source,
  required super.start,
  required super.end,

  /// The written type parameters, or `null` when omitted.
  final TypeParameterList? typeParameters,

  /// The nested formal parameter list.
  required final FormalParameterList parameters,

  /// The offset of the nullable `?`, or `null` when absent.
  final int? questionOffset,
}) extends AstNode {
  this {
    _checkChildren(this);
    if (questionOffset case final offset?) {
      RangeError.checkValueInInterval(
        offset,
        parameters.end,
        end - 1,
        'questionOffset',
      );
    }
  }

  @override
  int get childCount => typeParameters == null ? 1 : 2;
  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return typeParameters != null && index == 0 ? typeParameters! : parameters;
  }
}

/// A formal parameter's default expression, including `=` or legacy `:`.
final class ParameterDefault({
  required super.source,
  required super.start,
  required super.end,

  /// The written separator before [value].
  final ParameterDefaultSeparator separator = .equals,

  /// The written default, before constant evaluation.
  required final Expression value,
}) extends AstNode {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount => 1;
  @override
  AstNode childAt(int index) => switch (index) {
    0 => value,
    _ => super.childAt(index),
  };
}
