import 'type.dart';

/// Canonical identities for the core collection protocols and literal types.
abstract final class CoreTypes() {
  static ClassType _declare(String name, int arity, {bool sequence = false}) {
    final parameters = [
      for (var i = 0; i < arity; i++)
        TypeParameterType('T$i')..initializeBound(ValueType.object.nullable),
    ];
    final type = ClassType.declare(
      Uri.parse('dart:core'),
      name,
      typeParameters: parameters,
      isAbstract: true,
    );
    type.initializeHierarchy(
      interfaces: sequence ? [iterableOf(parameters.single)] : [],
    );
    return type;
  }

  static final ClassType iterable = _declare('Iterable', 1);
  static final ClassType iterator = _declare('Iterator', 1);
  static final ClassType list = _declare('List', 1, sequence: true);
  static final ClassType set = _declare('Set', 1, sequence: true);
  static final ClassType map = _declare('Map', 2);

  static ClassType iterableOf(ValueType element) =>
      iterable.instantiate([element]);
  static ClassType iteratorOf(ValueType element) =>
      iterator.instantiate([element]);
  static ClassType listOf(ValueType element) => list.instantiate([element]);
  static ClassType setOf(ValueType element) => set.instantiate([element]);
  static ClassType mapOf(ValueType key, ValueType value) =>
      map.instantiate([key, value]);

  /// Resolves an inherited protocol without erasing its arguments.
  static ClassType? view(ValueType type, ClassType declaration) {
    if (type is TypeParameterType) return view(type.bound, declaration);
    if (type is NonNullableTypeParameterType) {
      return view(type.parameter.bound.nonNullable, declaration);
    }
    return type is ClassType ? type.asInstanceOf(declaration) : null;
  }
}
