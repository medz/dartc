part of '../nodes.dart';

/// A written type, without a resolved semantic type.
sealed class TypeAnnotation({
  required super.source,
  required super.start,
  required super.end,

  /// The offset of the nullable `?`, or `null` when absent.
  final int? questionOffset,
}) extends AstNode {
  this {
    final offset = questionOffset;
    if (offset != null) {
      RangeError.checkValueInInterval(offset, start, end - 1, 'questionOffset');
    }
  }

  /// Whether a nullable `?` is present.
  bool get isNullable => questionOffset != null;
}

/// A type name, optionally qualified, parameterized, or nullable.
///
/// Keyword types such as `void` and `dynamic` use the same name representation.
final class NamedTypeAnnotation({
  required super.source,
  required super.start,
  required super.end,
  super.questionOffset,

  /// The written import prefix, or `null` when absent.
  final Identifier? prefix,

  /// The written type name.
  required final Identifier name,

  /// The explicit type arguments, or `null` when omitted.
  final TypeArgumentList? typeArguments,
}) extends TypeAnnotation {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      (prefix == null ? 0 : 1) + 1 + (typeArguments == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (prefix != null) {
      if (index == 0) return prefix!;
      index--;
    }
    return index == 0 ? name : typeArguments!;
  }
}

/// Explicit type arguments, including their angle brackets.
final class TypeArgumentList({
  required super.source,
  required super.start,
  required super.end,
  required List<TypeAnnotation> arguments,
}) extends AstNode {
  /// The arguments in source order, copied into an unmodifiable list.
  final List<TypeAnnotation> arguments = _freeze(arguments);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => arguments.length;
  @override
  AstNode childAt(int index) => arguments[index];
}

/// A function type written with `Function`, including generic function types.
final class FunctionTypeAnnotation({
  required super.source,
  required super.start,
  required super.end,
  super.questionOffset,

  /// The return type, or `null` when it was omitted.
  final TypeAnnotation? returnType,

  /// The type parameters, or `null` for a nongeneric function type.
  final TypeParameterList? typeParameters,

  /// The written parameter types.
  required final FunctionTypeParameterList parameters,
}) extends TypeAnnotation {
  this {
    _checkChildren(this);
  }

  @override
  int get childCount =>
      (returnType == null ? 0 : 1) + (typeParameters == null ? 0 : 1) + 1;

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (returnType != null) {
      if (index == 0) return returnType!;
      index--;
    }
    if (typeParameters != null) {
      if (index == 0) return typeParameters!;
      index--;
    }
    return parameters;
  }
}

/// Declared type parameters, including their angle brackets.
final class TypeParameterList({
  required super.source,
  required super.start,
  required super.end,
  required List<TypeParameter> parameters,
}) extends AstNode {
  /// The parameters in declaration order, copied into an unmodifiable list.
  final List<TypeParameter> parameters = _freeze(parameters);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => parameters.length;
  @override
  AstNode childAt(int index) => parameters[index];
}

/// A type parameter with its metadata and optional `extends` bound.
final class TypeParameter({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The declared name, including `_` when written.
  required final Identifier name,

  /// The explicit upper bound, or `null` when omitted.
  final TypeAnnotation? bound,
}) extends AstNode {
  /// The annotations in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 1 + (bound == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    return index == metadata.length ? name : bound!;
  }
}

/// The position and optionality written for a function-type parameter.
enum FunctionTypeParameterKind {
  requiredPositional,
  optionalPositional,
  optionalNamed,
  requiredNamed,
}

/// The parameters of a function type, including their parentheses.
final class FunctionTypeParameterList({
  required super.source,
  required super.start,
  required super.end,
  required List<FunctionTypeParameter> parameters,
}) extends AstNode {
  /// The parameters in source order, copied into an unmodifiable list.
  final List<FunctionTypeParameter> parameters = _freeze(parameters);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => parameters.length;
  @override
  AstNode childAt(int index) => parameters[index];
}

/// One function-type parameter and its optional written name.
final class FunctionTypeParameter({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The parameter's position and optionality.
  required final FunctionTypeParameterKind kind,

  /// The written type.
  required final TypeAnnotation type,

  /// The written name, or `null` when omitted.
  final Identifier? name,
}) extends AstNode {
  /// The annotations in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => metadata.length + 1 + (name == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    return index == metadata.length ? type : name!;
  }
}

/// A record type with positional fields and an optional named-field section.
final class RecordTypeAnnotation({
  required super.source,
  required super.start,
  required super.end,
  super.questionOffset,
  List<PositionalRecordTypeField> positionalFields = const [],

  /// The named-field section, or `null` when absent.
  final RecordTypeNamedFields? namedFields,
}) extends TypeAnnotation {
  /// The positional fields in source order, copied into an unmodifiable list.
  final List<PositionalRecordTypeField> positionalFields = _freeze(
    positionalFields,
  );

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => positionalFields.length + (namedFields == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    return index < positionalFields.length
        ? positionalFields[index]
        : namedFields!;
  }
}

/// A field in a record type.
sealed class RecordTypeField({
  required super.source,
  required super.start,
  required super.end,
  List<Annotation> metadata = const [],

  /// The field's written type.
  required final TypeAnnotation type,
}) extends AstNode {
  /// The annotations in source order, copied into an unmodifiable list.
  final List<Annotation> metadata = _freeze(metadata);

  /// The written name, or `null` for an unnamed positional field.
  Identifier? get name;

  @override
  int get childCount => metadata.length + 1 + (name == null ? 0 : 1);

  @override
  AstNode childAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount);
    if (index < metadata.length) return metadata[index];
    return index == metadata.length ? type : name!;
  }
}

/// A positional record-type field, with an optional documentation name.
final class PositionalRecordTypeField({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,
  required super.type,
  this.name,
}) extends RecordTypeField {
  @override
  final Identifier? name;

  this {
    _checkChildren(this);
  }
}

/// A named record-type field.
final class NamedRecordTypeField({
  required super.source,
  required super.start,
  required super.end,
  super.metadata,
  required super.type,
  required this.name,
}) extends RecordTypeField {
  @override
  final Identifier name;

  this {
    _checkChildren(this);
  }
}

/// Named record-type fields, including their braces.
final class RecordTypeNamedFields({
  required super.source,
  required super.start,
  required super.end,
  required List<NamedRecordTypeField> fields,
}) extends AstNode {
  /// The fields in source order, copied into an unmodifiable list.
  final List<NamedRecordTypeField> fields = _freeze(fields);

  this {
    _checkChildren(this);
  }

  @override
  int get childCount => fields.length;
  @override
  AstNode childAt(int index) => fields[index];
}

/// A zero-width placeholder for a missing type annotation.
final class MissingTypeAnnotation({required super.source, required int offset})
    extends TypeAnnotation {
  this : super(start: offset, end: offset);
}
