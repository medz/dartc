import 'signature.dart';
import 'type.dart';

/// Canonical identities and storage for supported core nominal types.
abstract final class CoreTypes() {
  static ClassType _declare(
    String name,
    int arity, {
    bool sequence = false,
    bool isAbstract = true,
  }) {
    final parameters = [
      for (var i = 0; i < arity; i++)
        TypeParameterType('T$i')
          ..initializeBound(ValueType.object.nullable)
          ..initializeDefaultType(ValueType.dynamicType),
    ];
    final type = ClassType.declare(
      Uri.parse('dart:core'),
      name,
      typeParameters: parameters,
      isAbstract: isAbstract,
    );
    type.initializeHierarchy(
      interfaces: sequence ? [iterableOf(parameters.single)] : [],
    );
    return type;
  }

  static final ClassType enumeration = _declare('Enum', 0);
  static final InstanceField enumIndex = InstanceField(
    enumeration,
    'index',
    ValueType.integer,
    isFinal: true,
  );
  static final InstanceField enumName = InstanceField(
    enumeration,
    '_name',
    ValueType.string,
    isFinal: true,
  );

  static final ClassType symbol = _declare('Symbol', 0);

  /// Built-in Symbol storage, distinct from user implementations of Symbol.
  static final ClassType symbolStorage = ClassType(
    Uri.parse('dart:_internal'),
    'Symbol',
    interfaces: [symbol],
  );
  static final InstanceField symbolName = InstanceField(
    symbolStorage,
    '_name',
    ValueType.string,
    isFinal: true,
  );

  /// A private name's declaring library URI, or null for a public constructor.
  static final InstanceField symbolPrivateLibrary = InstanceField(
    symbolStorage,
    '_privateLibrary',
    ValueType.string.nullable,
    isFinal: true,
  );

  static final ClassType invocation = _declare('Invocation', 0);

  /// Factory-created Invocation storage, separate from user implementations.
  static final ClassType invocationStorage = ClassType(
    Uri.parse('dart:core'),
    '_Invocation',
    interfaces: [invocation],
  );
  static final InstanceField invocationMemberName = InstanceField(
    invocationStorage,
    'memberName',
    symbol,
    isFinal: true,
  );
  static final InstanceField invocationTypeArguments = InstanceField(
    invocationStorage,
    'typeArguments',
    listOf(ValueType.typeType),
    isFinal: true,
  );
  static final InstanceField invocationPositionalArguments = InstanceField(
    invocationStorage,
    'positionalArguments',
    listOf(ValueType.dynamicType),
    isFinal: true,
  );
  static final InstanceField invocationNamedArguments = InstanceField(
    invocationStorage,
    'namedArguments',
    mapOf(symbol, ValueType.dynamicType),
    isFinal: true,
  );

  /// Method (0), getter (1), or setter (2); the public flags are derived.
  static final InstanceField invocationKind = InstanceField(
    invocationStorage,
    '_kind',
    ValueType.integer,
    isFinal: true,
  );

  /// Canonical asynchronous result protocol; FutureOr is a union, not a class.
  static final ClassType future = ValueType.future;
  static ClassType futureOf(ValueType value) => future.instantiate([value]);

  static final ClassType iterable = _declare('Iterable', 1);
  static final ClassType iterator = _declare('Iterator', 1);
  static final ClassType list = _declare('List', 1, sequence: true);
  static final ClassType set = _declare('Set', 1, sequence: true);
  static final ClassType map = _declare('Map', 2);
  static final ClassType mapEntry = _declare('MapEntry', 2, isAbstract: false);
  static final InstanceField mapEntryKey = InstanceField(
    mapEntry,
    'key',
    mapEntry.typeParameters[0],
    isFinal: true,
  );
  static final InstanceField mapEntryValue = InstanceField(
    mapEntry,
    'value',
    mapEntry.typeParameters[1],
    isFinal: true,
  );

  static ClassType iterableOf(ValueType element) =>
      iterable.instantiate([element]);
  static ClassType iteratorOf(ValueType element) =>
      iterator.instantiate([element]);
  static ClassType listOf(ValueType element) => list.instantiate([element]);
  static ClassType setOf(ValueType element) => set.instantiate([element]);
  static ClassType mapOf(ValueType key, ValueType value) =>
      map.instantiate([key, value]);

  static ClassType mapEntryOf(ValueType key, ValueType value) =>
      mapEntry.instantiate([key, value]);

  /// Resolves an inherited protocol without erasing its arguments.
  static ClassType? view(ValueType type, ClassType declaration) =>
      _view(type, declaration, null);

  static ClassType? _view(
    ValueType type,
    ClassType declaration,
    Set<TypeParameterType>? active,
  ) {
    if (type case PromotedTypeParameterType(:final parameter, :final bound)) {
      final nonNullable = !type.mayBeNull;
      if (nonNullable && declaration == ValueType.object) {
        return ValueType.object;
      }
      return _view(
            nonNullable ? bound.nonNullable : bound,
            declaration,
            active,
          ) ??
          _view(parameter, declaration, active);
    }
    if (type is NonNullableTypeParameterType &&
        declaration == ValueType.object) {
      return ValueType.object;
    }
    final parameter = switch (type) {
      TypeParameterType() => type,
      NonNullableTypeParameterType(:final parameter) => parameter,
      _ => null,
    };
    if (parameter != null) {
      active ??= {};
      if (!active.add(parameter)) return null;
      try {
        return _view(
          type is NonNullableTypeParameterType
              ? parameter.bound.nonNullable
              : parameter.bound,
          declaration,
          active,
        );
      } finally {
        active.remove(parameter);
      }
    }
    if (type is FutureOrType) {
      final value = _view(type.argument, declaration, active);
      final future = _view(type.futureType, declaration, active);
      if (value == null || future == null) return null;
      // Retain a common existing view, without conflating the union's identity.
      if (value.accepts(future)) return value;
      if (future.accepts(value)) return future;
      return null;
    }
    return type is ClassType ? type.asInstanceOf(declaration) : null;
  }
}
