/// The Dart type of an IR operand or function result.
enum ValueType() {
  /// A non-nullable Dart `bool`.
  boolean,

  /// A non-nullable Dart `int`.
  integer,

  /// The declared result of a `void` function, which can still return a value.
  voidType,
}

/// The identity and signature of a directly callable top-level function.
///
/// Use the same target object for a function's definition and all its calls.
final class FunctionTarget(
  /// The URI of the library that declares the function.
  final Uri library,

  /// The declared name within [library].
  final String name,

  /// The static type of the result.
  final ValueType returnType,
  Iterable<ValueType> parameters,
) {
  /// The parameter types in declaration order.
  final List<ValueType> parameterTypes = .unmodifiable(parameters);

  /// Creates a target with a snapshot of [parameters].
  ///
  /// Throws [ArgumentError] if a parameter has type [ValueType.voidType].
  this {
    if (parameterTypes.contains(ValueType.voidType)) {
      throw ArgumentError('A parameter must carry a value.');
    }
  }
}
