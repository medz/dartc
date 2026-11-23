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
  final TypeList? required;
  final TypeList? optional;

  /// In the order of their names.
  final NamedList? named;
  const FunctionType(this.result, this.required, this.optional, this.named);
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

final class NamedList {
  final int name;
  final RuntimeType type;
  final bool isRequired;
  final NamedList? tail;
  const NamedList(this.name, this.type, this.isRequired, this.tail);
}

/// The supertypes of a class, in terms of its parameters.
final class SuperList {
  final int number;
  final TypeList? arguments;
  final SuperList? tail;
  const SuperList(this.number, this.arguments, this.tail);
}
