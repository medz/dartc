/// A static SSA type. Source values carry Dart types; capture cells carry a storage type.
sealed class const ValueType() {
  /// The non-nullable `Object` type.
  static const ClassType object = ClassType._core('Object', null, false);

  /// The common supertype of `int` and `double`.
  static const ClassType number = ClassType._core('num', object, true);

  /// The non-nullable `int` type.
  static const ClassType integer = ClassType._core('int', number, true);

  /// The non-nullable `double` type.
  static const ClassType floating = ClassType._core('double', number, true);

  /// The non-nullable `bool` type.
  static const ClassType boolean = ClassType._core('bool', object, true);

  /// The non-nullable `String` type.
  static const ClassType string = ClassType._core('String', object, true);

  /// The common supertype of all Dart record shapes.
  static const ClassType record = ClassType._core('Record', object, true);

  /// The supertype of all function values.
  static const ClassType function = ClassType._core('Function', object, true);

  /// The Dart trace paired with a caught exception.
  static const ClassType stackTrace = ClassType._core(
    'StackTrace',
    object,
    true,
  );

  /// The superclass of Dart runtime errors.
  static const ClassType error = ClassType._core('Error', object, false);

  /// The error raised by failed runtime type checks.
  static const ClassType typeError = ClassType._core('TypeError', error, false);

  /// The error raised by an enabled failed assertion.
  static const ClassType assertionError = ClassType._core(
    'AssertionError',
    error,
    false,
  );

  /// The type whose only value is `null`.
  static const ValueType nullType = _SpecialType('Null');

  /// The type with no values.
  static const ValueType never = _SpecialType('Never');

  /// The top type whose uses Dart restricts statically.
  static const ValueType voidType = _SpecialType('void');

  /// The spelling used in a Dart type annotation.
  String get dartName;

  /// Whether a runtime inhabitant may be null, distinct from accepting a null assignment.
  bool get mayBeNull => switch (this) {
    TypeParameterType() => (this as TypeParameterType).bound.mayBeNull,
    NonNullableTypeParameterType() => false,
    _NullableType() => true,
    _ => this == nullType || this == voidType,
  };

  /// The union of this type and `Null`.
  ValueType get nullable {
    if (this == never) return nullType;
    return accepts(nullType) ? this : _NullableType(this);
  }

  /// The static type after Dart's postfix null assertion.
  ValueType get nonNullable => this == nullType ? never : this;

  /// Whether Dart equality on this receiver can only use a core scalar implementation.
  bool get hasScalarEquality {
    final base = nonNullable;
    return number.accepts(base) || base == boolean || base == string;
  }

  /// Whether an operand of [type] can be passed here without a conversion.
  bool accepts(ValueType type) {
    if (this is CellType || type is CellType) return this == type;
    if (this == type || type == never || this == voidType) return true;
    if (this is TypeParameterType) {
      if (type is NonNullableTypeParameterType) {
        return identical(type.parameter, this) ||
            accepts(type.parameter.bound.nonNullable);
      }
      return type is TypeParameterType && accepts(type.bound);
    }
    if (this case NonNullableTypeParameterType(:final parameter)) {
      return !type.mayBeNull && parameter.accepts(type);
    }
    if (this case _NullableType(:final nonNullable)) {
      return type == nullType ||
          nonNullable == object ||
          nonNullable.accepts(type.nonNullable);
    }
    if (type is NonNullableTypeParameterType) {
      return this == object || accepts(type.parameter.bound.nonNullable);
    }
    if (type is TypeParameterType) {
      // Only the bound is known about an arbitrary value of a type variable.
      return accepts(type.bound);
    }
    if (type is FunctionType) {
      final target = this;
      return target is FunctionType
          ? target._accepts(type)
          : target == function || target == object;
    }
    if (type is RecordType) {
      final target = this;
      if (target is! RecordType) return target == record || target == object;
      return target.sameShape(type) &&
          target.fields.indexed.every((p) => p.$2.accepts(type.fields[p.$1]));
    }
    return this is ClassType &&
        type is ClassType &&
        type._inherits(this as ClassType);
  }
}

/// An internal reference to a captured variable with invariant [content] type.
final class CellType(
  /// The Dart type stored in the shared variable.
  final ValueType content,
) extends ValueType {
  this {
    if (content is CellType) {
      throw ArgumentError('A captured slot must hold a Dart value.');
    }
  }

  @override
  ValueType get nullable =>
      throw UnsupportedError('Capture storage cannot be nullable.');
  @override
  String get dartName => 'cell<${content.dartName}>';
  @override
  bool operator ==(Object other) =>
      other is CellType && other.content == content;
  @override
  int get hashCode => Object.hash(CellType, content);
}

/// A structural record type with positional slots followed by named slots in name order.
final class RecordType._(
  /// The number of positional fields.
  final int positionalCount,

  /// The static field types in slot order.
  final List<ValueType> fields,

  /// The slot of each getter, including positional getters such as `$1`.
  final Map<String, int> slots,
) extends ValueType {
  /// Creates a type from [positional] types and resolved [named] field names.
  ///
  /// Throws [ArgumentError] for an empty, private, reserved or conflicting field name.
  factory(
    Iterable<ValueType> positional, [
    Map<String, ValueType> named = const {},
  ]) {
    final fields = positional.toList();
    final count = fields.length;
    final slots = {for (var i = 0; i < count; i++) '\$${i + 1}': i};
    final names = named.keys.toList()..sort();
    for (final name in names) {
      if (name.isEmpty ||
          name.startsWith('_') ||
          slots.containsKey(name) ||
          const {
            'hashCode',
            'runtimeType',
            'toString',
            'noSuchMethod',
          }.contains(name)) {
        throw ArgumentError.value(name, 'named', 'Invalid record field');
      }
      slots[name] = fields.length;
      fields.add(named[name]!);
    }
    if (fields.any((t) => t is CellType)) {
      throw ArgumentError('Record fields must hold Dart values.');
    }
    return ._(count, .unmodifiable(fields), .unmodifiable(slots));
  }

  /// Whether [other] has the same positional count and named getters.
  bool sameShape(RecordType other) =>
      positionalCount == other.positionalCount &&
      fields.length == other.fields.length &&
      slots.keys.every(other.slots.containsKey);

  @override
  String get dartName {
    final parts = [
      for (var i = 0; i < positionalCount; i++) fields[i].dartName,
    ];
    final named = [
      for (final e in slots.entries.skip(positionalCount))
        '${fields[e.value].dartName} ${e.key}',
    ];
    if (named.isNotEmpty) parts.add('{${named.join(', ')}}');
    return '(${parts.join(', ')}${positionalCount == 1 && named.isEmpty ? ',' : ''})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordType &&
          sameShape(other) &&
          fields.indexed.every((p) => p.$2 == other.fields[p.$1]);

  @override
  int get hashCode => Object.hash(
    positionalCount,
    Object.hashAll(slots.keys),
    Object.hashAll(fields),
  );
}

/// A possibly generic Dart function type with positional and named parameter slots.
final class FunctionType._(
  final List<TypeParameterType> typeParameters,

  /// The result visible at a call site.
  final ValueType result,

  /// Explicit parameter types in declaration order.
  final List<ValueType> parameters,

  /// The number of positional parameters, including optional ones.
  final int positionalCount,

  /// The number of positional arguments that must be supplied.
  final int requiredPositional,

  /// Named parameter slots and requiredness.
  final Map<String, ({int slot, bool required})> named,
) extends ValueType {
  /// Builds a signature. Named parameters occupy the last slots in map order.
  factory(
    ValueType result,
    Iterable<ValueType> parameters, {
    int optionalPositional = 0,
    Map<String, bool> namedParameters = const {},
    Iterable<TypeParameterType> typeParameters = const [],
  }) {
    final types = List<ValueType>.unmodifiable(parameters);
    if (result is CellType || types.any((t) => t is CellType)) {
      throw ArgumentError('Function signatures must contain Dart types.');
    }
    final count = types.length - namedParameters.length;
    if (optionalPositional < 0 ||
        optionalPositional > count ||
        optionalPositional > 0 && namedParameters.isNotEmpty) {
      throw ArgumentError('Invalid optional and named parameter counts.');
    }
    final binders = List<TypeParameterType>.unmodifiable(typeParameters);
    if (binders.toSet().length != binders.length) {
      throw ArgumentError('Repeated function type parameter.');
    }
    return ._(
      binders,
      result,
      types,
      count,
      count - optionalPositional,
      .unmodifiable({
        for (final (i, e) in namedParameters.entries.indexed)
          e.key: (slot: count + i, required: e.value),
      }),
    );
  }

  /// Applies every function type argument simultaneously and checks its bound.
  FunctionType instantiate(Iterable<ValueType> arguments) {
    final args = List<ValueType>.unmodifiable(arguments);
    if (args.length != typeParameters.length ||
        args.any((t) => t is CellType)) {
      throw ArgumentError('Invalid function type arguments.');
    }
    final environment = {
      for (final (i, parameter) in typeParameters.indexed) parameter: args[i],
    };
    for (final (i, parameter) in typeParameters.indexed) {
      if (!substituteType(parameter.bound, environment).accepts(args[i])) {
        throw ArgumentError(
          'Type argument does not satisfy ${parameter.name} bound.',
        );
      }
    }
    return _bodyWith(environment);
  }

  FunctionType _bodyWith(Map<TypeParameterType, ValueType> environment) =>
      FunctionType(
        substituteType(result, environment),
        parameters.map((t) => substituteType(t, environment)),
        optionalPositional: positionalCount - requiredPositional,
        namedParameters: {
          for (final e in named.entries) e.key: e.value.required,
        },
      );

  Map<TypeParameterType, ValueType>? _relate(FunctionType other) {
    if (typeParameters.length != other.typeParameters.length) return null;
    final environment = <TypeParameterType, ValueType>{
      for (final (i, parameter) in other.typeParameters.indexed)
        parameter: typeParameters[i],
    };
    for (final (i, parameter) in typeParameters.indexed) {
      if (parameter.bound !=
          substituteType(other.typeParameters[i].bound, environment)) {
        return null;
      }
    }
    return environment;
  }

  /// Slots whose values can be supplied by the destination's defaults.
  Iterable<int> get optionalSlots sync* {
    for (var i = requiredPositional; i < positionalCount; i++) {
      yield i;
    }
    for (final p in named.values) {
      if (!p.required) yield p.slot;
    }
  }

  /// Places supplied arguments in declaration order and fills omitted slots.
  List<T> bind<T>(
    List<T> positional,
    Map<String, T> supplied,
    T Function(int) omitted,
  ) {
    if (positional.length < requiredPositional ||
        positional.length > positionalCount ||
        supplied.keys.any((name) => !named.containsKey(name))) {
      throw ArgumentError('Arguments do not match $dartName.');
    }
    final values = <T>[...positional];
    while (values.length < positionalCount) {
      values.add(omitted(values.length));
    }
    for (final MapEntry(:key, value: p) in named.entries) {
      if (supplied.containsKey(key)) {
        values.add(supplied[key] as T);
      } else if (p.required) {
        throw ArgumentError('Missing required argument $key.');
      } else {
        values.add(omitted(p.slot));
      }
    }
    return values;
  }

  bool _accepts(FunctionType actual) {
    final environment = _relate(actual);
    if (environment == null) return false;
    if (typeParameters.isNotEmpty) {
      return _bodyWith(const {})._accepts(actual._bodyWith(environment));
    }
    if (!result.accepts(actual.result) ||
        actual.requiredPositional > requiredPositional ||
        actual.positionalCount < positionalCount) {
      return false;
    }
    for (var i = 0; i < positionalCount; i++) {
      if (!actual.parameters[i].accepts(parameters[i])) return false;
    }
    for (final MapEntry(:key, value: p) in named.entries) {
      final q = actual.named[key];
      if (q == null || !actual.parameters[q.slot].accepts(parameters[p.slot])) {
        return false;
      }
    }
    return actual.named.entries.every(
      (e) => !e.value.required || named[e.key]?.required == true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FunctionType) return false;
    final environment = _relate(other);
    if (environment == null) return false;
    final actual = other._bodyWith(environment);
    return result == actual.result &&
        positionalCount == actual.positionalCount &&
        requiredPositional == actual.requiredPositional &&
        named.length == actual.named.length &&
        parameters
            .take(positionalCount)
            .indexed
            .every((p) => p.$2 == actual.parameters[p.$1]) &&
        named.entries.every((e) {
          final p = actual.named[e.key];
          return p != null &&
              p.required == e.value.required &&
              parameters[e.value.slot] == actual.parameters[p.slot];
        });
  }

  @override
  int get hashCode => _typeHash(this, const {});

  @override
  String get dartName {
    final parts = [
      for (final p in parameters.take(requiredPositional)) p.dartName,
    ];
    if (requiredPositional < positionalCount) {
      parts.add(
        '[${parameters.getRange(requiredPositional, positionalCount).map((p) => p.dartName).join(', ')}]',
      );
    }
    if (named.isNotEmpty) {
      final fields = [
        for (final MapEntry(:key, value: p) in named.entries)
          '${p.required ? 'required ' : ''}${parameters[p.slot].dartName} $key',
      ];
      parts.add('{${fields.join(', ')}}');
    }
    final binders = typeParameters.isEmpty
        ? ''
        : '<${typeParameters.map((p) => '${p.name} extends ${p.bound.dartName}').join(', ')}>';
    return '${result.dartName} Function$binders(${parts.join(', ')})';
  }
}

/// A nominal declaration, or an applied view of that declaration.
final class const ClassType._(
  final Uri? _library,
  final String name,
  final ClassType? _superclass,
  final List<ClassType> _interfaces,
  final bool isAbstract,
  final List<TypeParameterType> typeParameters,
  final List<ValueType> typeArguments,
  final ClassType? _declaration,
  final _ClassHierarchy? _hierarchy,
) extends ValueType {
  new(
    Uri library,
    String name, {
    ClassType superclass = ValueType.object,
    Iterable<ClassType> interfaces = const [],
    bool isAbstract = false,
    Iterable<TypeParameterType> typeParameters = const [],
  }) : this._(
         library,
         name,
         superclass,
         .unmodifiable(interfaces),
         isAbstract,
         .unmodifiable(typeParameters),
         .unmodifiable(typeParameters),
         null,
         null,
       );

  const new _core(String name, ClassType? parent, bool isAbstract)
    : this._(
        null,
        name,
        parent,
        const [],
        isAbstract,
        const [],
        const [],
        null,
        null,
      );

  new declare(
    Uri library,
    String name, {
    Iterable<TypeParameterType> typeParameters = const [],
    bool isAbstract = false,
  }) : this._(
         library,
         name,
         null,
         const [],
         isAbstract,
         .unmodifiable(typeParameters),
         .unmodifiable(typeParameters),
         null,
         _ClassHierarchy(),
       );

  void initializeHierarchy({
    ClassType superclass = ValueType.object,
    Iterable<ClassType> interfaces = const [],
  }) {
    final hierarchy = declaration._hierarchy;
    if (hierarchy == null || hierarchy.initialized) {
      throw StateError('Class hierarchy already initialized.');
    }
    hierarchy.superclass = superclass;
    hierarchy.interfaces = List.unmodifiable(interfaces);
    hierarchy.initialized = true;
  }

  static final _coreLibrary = Uri.parse('dart:core');
  Uri get library => _library ?? _coreLibrary;
  ClassType get declaration => _declaration ?? this;
  Map<TypeParameterType, ValueType> get typeEnvironment => {
    for (final (i, parameter) in typeParameters.indexed)
      parameter: typeArguments[i],
  };
  ClassType? get superclass {
    final parent =
        declaration._hierarchy?.superclass ?? declaration._superclass;
    return parent == null
        ? null
        : substituteType(parent, typeEnvironment) as ClassType;
  }

  List<ClassType> get interfaces => [
    for (final type
        in (declaration._hierarchy?.interfaces ?? declaration._interfaces))
      substituteType(type, typeEnvironment) as ClassType,
  ];
  @override
  String get dartName => typeArguments.isEmpty
      ? name
      : '$name<${typeArguments.map((t) => t.dartName).join(', ')}>';

  /// Applies this declaration, retaining every type argument.
  ClassType instantiate(Iterable<ValueType> arguments) {
    final args = List<ValueType>.unmodifiable(arguments);
    final owner = declaration;
    if (args.length != owner.typeParameters.length ||
        args.any((t) => t is CellType)) {
      throw ArgumentError('Invalid class type arguments.');
    }
    if (args.indexed.every((e) => e.$2 == owner.typeParameters[e.$1])) {
      return owner;
    }
    return ClassType._(
      owner._library,
      owner.name,
      null,
      const [],
      owner.isAbstract,
      owner.typeParameters,
      args,
      owner,
      null,
    );
  }

  /// Checks all instantiated arguments against their simultaneously substituted bounds.
  void validateTypeArguments() {
    for (final (i, parameter) in typeParameters.indexed) {
      final bound = substituteType(parameter.bound, typeEnvironment);
      if (!bound.accepts(typeArguments[i])) {
        throw ArgumentError(
          'Type argument does not satisfy ${parameter.name} bound.',
        );
      }
    }
  }

  /// Projects this view onto a superclass or implemented interface declaration.
  ClassType? asInstanceOf(ClassType owner, [Set<ClassType>? visited]) {
    if (identical(declaration, owner.declaration)) return this;
    visited ??= {};
    if (!visited.add(declaration)) return null;
    final parent = superclass?.asInstanceOf(owner, visited);
    if (parent != null) return parent;
    for (final interface in interfaces) {
      final found = interface.asInstanceOf(owner, visited);
      if (found != null) return found;
    }
    return null;
  }

  bool _inherits(ClassType target) {
    final view = asInstanceOf(target);
    return view != null &&
        target.typeArguments.indexed.every(
          (e) => e.$2.accepts(view.typeArguments[e.$1]),
        );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassType &&
          identical(declaration, other.declaration) &&
          typeArguments.length == other.typeArguments.length &&
          typeArguments.indexed.every((e) => e.$2 == other.typeArguments[e.$1]);
  @override
  int get hashCode =>
      Object.hash(identityHashCode(declaration), Object.hashAll(typeArguments));
}

final class _ClassHierarchy() {
  bool initialized = false;
  ClassType? superclass;
  List<ClassType> interfaces = const [];
}

/// A lexically scoped type variable. Equal names do not imply equal identities.
final class TypeParameterType(final String name) extends ValueType {
  ValueType? _bound;
  ValueType get bound =>
      _bound ?? (throw StateError('Uninitialized type parameter bound.'));
  void initializeBound(ValueType type) {
    if (_bound != null || type is CellType) {
      throw StateError('Invalid type parameter bound initialization.');
    }
    _bound = type;
  }

  @override
  String get dartName => name;
  @override
  ValueType get nonNullable => NonNullableTypeParameterType(this);
}

/// The intersection of a type variable with non-nullable Object.
final class NonNullableTypeParameterType(final TypeParameterType parameter)
    extends ValueType {
  @override
  String get dartName => '${parameter.dartName} & Object';
  @override
  bool operator ==(Object other) =>
      other is NonNullableTypeParameterType &&
      identical(parameter, other.parameter);
  @override
  int get hashCode => Object.hash(NonNullableTypeParameterType, parameter);
}

/// Simultaneous, capture-free substitution of type variable identities.
ValueType substituteType(
  ValueType type,
  Map<TypeParameterType, ValueType> environment,
) {
  if (environment.isEmpty) return type;
  return switch (type) {
    TypeParameterType() => environment[type] ?? type,
    NonNullableTypeParameterType(:final parameter) =>
      (environment[parameter] ?? parameter).nonNullable,
    _NullableType(:final base) => substituteType(base, environment).nullable,
    ClassType() =>
      type.typeArguments.isEmpty
          ? type
          : type.declaration.instantiate(
              type.typeArguments.map((t) => substituteType(t, environment)),
            ),
    CellType(:final content) => CellType(substituteType(content, environment)),
    RecordType() => RecordType(
      type.fields
          .take(type.positionalCount)
          .map((t) => substituteType(t, environment)),
      {
        for (final e in type.slots.entries.skip(type.positionalCount))
          e.key: substituteType(type.fields[e.value], environment),
      },
    ),
    FunctionType() => _substituteFunction(type, environment),
    _ => type,
  };
}

final class const _SpecialType(@override final String dartName)
    extends ValueType;

final class const _NullableType(final ValueType base) extends ValueType {
  @override
  ValueType get nonNullable => base.nonNullable;
  @override
  String get dartName => '${base.dartName}?';

  @override
  bool operator ==(Object other) =>
      other is _NullableType && base == other.base;

  @override
  int get hashCode => Object.hash(_NullableType, base);
}

/// Whether a type expression mentions any of the given lexical parameters.
bool containsTypeParameter(ValueType type, Set<TypeParameterType> parameters) =>
    switch (type) {
      TypeParameterType() => parameters.contains(type),
      NonNullableTypeParameterType(:final parameter) => parameters.contains(
        parameter,
      ),
      _NullableType(:final base) => containsTypeParameter(base, parameters),
      ClassType() => type.typeArguments.any(
        (t) => containsTypeParameter(t, parameters),
      ),
      RecordType() => type.fields.any(
        (t) => containsTypeParameter(t, parameters),
      ),
      FunctionType() => typeParametersIn(type).any(parameters.contains),
      CellType(:final content) => containsTypeParameter(content, parameters),
      _ => false,
    };

/// Whether a class variable requires a covariant check in a member parameter.
///
/// Occurrences in a nested generic function's bounds are invariant and require
/// a check regardless of the surrounding function-parameter polarity.
bool containsCovariantTypeParameter(
  ValueType type,
  Set<TypeParameterType> parameters, [
  bool positive = true,
]) => switch (type) {
  TypeParameterType() => positive && parameters.contains(type),
  NonNullableTypeParameterType(:final parameter) =>
    positive && parameters.contains(parameter),
  _NullableType(:final base) => containsCovariantTypeParameter(
    base,
    parameters,
    positive,
  ),
  ClassType() => type.typeArguments.any(
    (t) => containsCovariantTypeParameter(t, parameters, positive),
  ),
  RecordType() => type.fields.any(
    (t) => containsCovariantTypeParameter(t, parameters, positive),
  ),
  FunctionType() =>
    type.typeParameters.any(
          (p) => containsTypeParameter(
            p.bound,
            parameters.difference(type.typeParameters.toSet()),
          ),
        ) ||
        containsCovariantTypeParameter(
          type.result,
          parameters.difference(type.typeParameters.toSet()),
          positive,
        ) ||
        type.parameters.any(
          (t) => containsCovariantTypeParameter(
            t,
            parameters.difference(type.typeParameters.toSet()),
            !positive,
          ),
        ),
  _ => false,
};

/// Free lexical type-variable identities mentioned by a type expression.
Iterable<TypeParameterType> typeParametersIn(ValueType type) sync* {
  switch (type) {
    case TypeParameterType():
      yield type;
    case NonNullableTypeParameterType(:final parameter):
      yield parameter;
    case _NullableType(:final base):
      yield* typeParametersIn(base);
    case ClassType():
      for (final argument in type.typeArguments) {
        yield* typeParametersIn(argument);
      }
    case RecordType():
      for (final field in type.fields) {
        yield* typeParametersIn(field);
      }
    case FunctionType():
      final bound = type.typeParameters.toSet();
      for (final nested in [
        type.result,
        ...type.parameters,
        ...type.typeParameters.map((p) => p.bound),
      ]) {
        yield* typeParametersIn(nested).where((p) => !bound.contains(p));
      }
    case CellType(:final content):
      yield* typeParametersIn(content);
    default:
      break;
  }
}

FunctionType _substituteFunction(
  FunctionType type,
  Map<TypeParameterType, ValueType> environment,
) {
  if (!typeParametersIn(type).any(environment.containsKey)) return type;
  final fresh = [
    for (final p in type.typeParameters) TypeParameterType(p.name),
  ];
  final scoped = <TypeParameterType, ValueType>{
    ...environment,
    for (final (i, p) in type.typeParameters.indexed) p: fresh[i],
  };
  for (final (i, p) in fresh.indexed) {
    p.initializeBound(substituteType(type.typeParameters[i].bound, scoped));
  }
  final body = type._bodyWith(scoped);
  return FunctionType(
    body.result,
    body.parameters,
    typeParameters: fresh,
    optionalPositional: body.positionalCount - body.requiredPositional,
    namedParameters: {
      for (final e in body.named.entries) e.key: e.value.required,
    },
  );
}

int _typeHash(ValueType type, Map<TypeParameterType, int> scope) {
  return switch (type) {
    TypeParameterType() =>
      scope.containsKey(type)
          ? Object.hash(TypeParameterType, scope[type])
          : identityHashCode(type),
    NonNullableTypeParameterType(:final parameter) => Object.hash(
      NonNullableTypeParameterType,
      _typeHash(parameter, scope),
    ),
    _NullableType(:final base) => Object.hash(
      _NullableType,
      _typeHash(base, scope),
    ),
    ClassType() => Object.hash(
      identityHashCode(type.declaration),
      Object.hashAll(type.typeArguments.map((t) => _typeHash(t, scope))),
    ),
    CellType(:final content) => Object.hash(
      CellType,
      _typeHash(content, scope),
    ),
    RecordType() => Object.hash(
      RecordType,
      type.positionalCount,
      Object.hashAll(type.slots.keys),
      Object.hashAll(type.fields.map((t) => _typeHash(t, scope))),
    ),
    FunctionType() => _functionHash(type, scope),
    _ => type.hashCode,
  };
}

int _functionHash(FunctionType type, Map<TypeParameterType, int> scope) {
  final nested = {
    ...scope,
    for (final (i, p) in type.typeParameters.indexed) p: scope.length + i,
  };
  return Object.hash(
    FunctionType,
    type.typeParameters.length,
    Object.hashAll(type.typeParameters.map((p) => _typeHash(p.bound, nested))),
    _typeHash(type.result, nested),
    type.requiredPositional,
    Object.hashAll(
      type.parameters
          .take(type.positionalCount)
          .map((t) => _typeHash(t, nested)),
    ),
    Object.hashAllUnordered(
      type.named.entries.map(
        (e) => Object.hash(
          e.key,
          e.value.required,
          _typeHash(type.parameters[e.value.slot], nested),
        ),
      ),
    ),
  );
}
