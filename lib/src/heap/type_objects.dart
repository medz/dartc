// Types where they are known only when the program runs.

abstract class RuntimeType {
  const RuntimeType();
}

/// `dynamic`, `void`, `Object?`, `Object`, `Null` or `Never`.
final class BasicType extends RuntimeType {
  final int kind;
  const BasicType(this.kind);
}

const dynamicKind = 0, voidKind = 1, anyKind = 2;
const objectKind = 3, nullKind = 4, neverKind = 5;

/// A class, by its number, with type arguments.
final class InterfaceType extends RuntimeType {
  final int number;
  final TypeList? arguments;
  const InterfaceType(this.number, this.arguments);
}

/// [inner] or null. Types that include null anyway never have this form.
final class NullableType extends RuntimeType {
  final RuntimeType inner;
  const NullableType(this.inner);
}

final class FunctionType extends RuntimeType {
  final RuntimeType result;

  /// Positional types followed by named types in alphabetical order.
  final TypeList? parameters;
  final FunctionShape shape;
  const FunctionType(this.result, this.parameters, this.shape);
}

/// Equal shapes are the same object, including across type instantiations.
final class FunctionShape {
  final int required, positional;

  /// Text before each parameter type in print order, then before the result.
  final List<String> prefixes;
  final NamedParameter? names;
  const FunctionShape(
    this.required,
    this.positional,
    this.prefixes,
    this.names,
  );
}

/// A record type, whose last [fields] have [names], in their order.
///
/// Equal lists of names are the same.
final class RecordType extends RuntimeType {
  final TypeList? fields;
  final List<String> names;
  const RecordType(this.fields, this.names);
}

/// A value of [inner], or a future of one. Where that is the same as a simpler
/// type, types never have this form.
final class FutureOrType extends RuntimeType {
  final RuntimeType inner;
  const FutureOrType(this.inner);
}

/// A function type with type parameters, which have [bounds].
final class GenericType extends RuntimeType {
  final TypeList bounds;
  final FunctionType inner;
  const GenericType(this.bounds, this.inner);
}

/// A type parameter of the function type around, counted from the innermost
/// one on.
final class BoundType extends RuntimeType {
  final int index;
  const BoundType(this.index);
}

/// A type parameter of the class whose supertypes this is part of.
final class VariableType extends RuntimeType {
  final int index;
  const VariableType(this.index);
}

final class TypeList {
  final RuntimeType head;
  final TypeList? tail;
  const TypeList(this.head, this.tail);
}

/// A shared parameter description in name order. [position] is its printed slot.
final class NamedParameter {
  /// Equal parameter names are the same string.
  final String name;
  final int position;
  final bool isRequired;
  final NamedParameter? tail;
  const NamedParameter(this.name, this.position, this.isRequired, this.tail);
}

/// The supertypes of a class, in terms of its parameters.
final class SuperList {
  final int number;
  final TypeList? arguments;
  final SuperList? tail;
  const SuperList(this.number, this.arguments, this.tail);
}
