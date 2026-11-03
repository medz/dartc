enum ValueType { boolean, integer, voidType }

/// A resolved top-level declaration. Calls share this identity with its body.
final class FunctionTarget {
  final Uri library;
  final String name;
  final ValueType returnType;
  final List<ValueType> parameterTypes;

  FunctionTarget(
    this.library,
    this.name,
    this.returnType,
    Iterable<ValueType> parameters,
  ) : parameterTypes = List.unmodifiable(parameters) {
    if (parameterTypes.contains(ValueType.voidType)) {
      throw ArgumentError('A parameter must carry a value.');
    }
  }
}
