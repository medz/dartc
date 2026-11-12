import 'package:dartc/interop.dart';

/// A static SSA type. Source values carry Dart types; capture cells carry a storage type.
sealed class const ValueType() {
  /// Normalizes a source type for runtime equality and constant identity.
  ///
  /// Preserves declaration identity and default type metadata. Function
  /// binders are freshened without modifying this type or its static equality.
  ValueType normalize() {
    ValueType visit(ValueType type, Map<TypeParameterType, ValueType> scope) {
      switch (type) {
        case TypeParameterType():
          final seen = <TypeParameterType>{};
          ValueType bound = type;
          while (bound is TypeParameterType && seen.add(bound)) {
            bound = bound.bound;
          }
          return bound == never ? never : scope[type] ?? type;
        case _NullableType(:final base):
          return visit(base, scope).nullable;
        case FutureOrType(:final argument):
          return ValueType.futureOr(visit(argument, scope));
        case ClassType():
          return type.typeArguments.isEmpty
              ? type
              : type.declaration.instantiate(
                  type.typeArguments.map((t) => visit(t, scope)),
                );
        case RecordType():
          return RecordType(
            type.fields.take(type.positionalCount).map((t) => visit(t, scope)),
            {
              for (final entry in type.slots.entries.skip(type.positionalCount))
                entry.key: visit(type.fields[entry.value], scope),
            },
          );
        case FunctionType():
          final fresh = [
            for (final parameter in type.typeParameters)
              TypeParameterType(parameter.name),
          ];
          final nested = {
            ...scope,
            for (final (i, parameter) in type.typeParameters.indexed)
              parameter: fresh[i],
          };
          for (final (i, parameter) in type.typeParameters.indexed) {
            fresh[i].initializeBound(visit(parameter.bound, nested));
          }
          for (final (i, parameter) in type.typeParameters.indexed) {
            if (parameter.defaultType case final value?) {
              fresh[i].initializeDefaultType(visit(value, nested));
            }
          }
          return FunctionType(
            visit(type.result, nested),
            type.parameters.map((t) => visit(t, nested)),
            typeParameters: fresh,
            optionalPositional: type.optionalPositional,
            namedParameters: type.namedParameters,
          );
        case NonNullableTypeParameterType(:final parameter):
          final result = visit(parameter, scope);
          return object.accepts(parameter.bound) ? result : result.nonNullable;
        case PromotedTypeParameterType(
          :final parameter,
          :final bound,
          :final isNonNullable,
        ):
          final result = visit(parameter, scope),
              normalizedBound = visit(bound, scope);
          if (result == never ||
              normalizedBound == never ||
              isNonNullable && normalizedBound == nullType) {
            return never;
          }
          if (normalizedBound == dynamicType ||
              normalizedBound == voidType ||
              normalizedBound == object.nullable ||
              normalizedBound == result ||
              bound.accepts(parameter.bound)) {
            return isNonNullable && parameter.mayBeNull
                ? result.nonNullable
                : result;
          }
          if (normalizedBound == object) return result.nonNullable;
          return PromotedTypeParameterType(
            result as TypeParameterType,
            normalizedBound,
            isNonNullable:
                isNonNullable && parameter.mayBeNull && bound.mayBeNull,
          );
        case CellType():
          throw ArgumentError('Capture storage has no runtime type identity.');
        default:
          return type;
      }
    }

    return visit(this, const {});
  }

  /// Substitutes free type variables simultaneously without capturing binders.
  ValueType substitute(Map<TypeParameterType, ValueType> environment) {
    if (environment.isEmpty) return this;
    return switch (this) {
      final TypeParameterType type => environment[type] ?? type,
      // Renaming a lexical binder retains its static promotion. Instantiating
      // that binder erases the promoted bound, just as Dart's type substitution
      // does; runtime checks must test the promoted bound before this erasure.
      PromotedTypeParameterType(
        :final parameter,
        :final bound,
        :final isNonNullable,
      ) =>
        switch (environment[parameter] ?? parameter) {
          final TypeParameterType replacement => PromotedTypeParameterType(
            replacement,
            bound.substitute(environment),
            isNonNullable: isNonNullable,
          ),
          final replacement =>
            isNonNullable ? replacement.nonNullable : replacement,
        },
      NonNullableTypeParameterType(:final parameter) =>
        (environment[parameter] ?? parameter).nonNullable,
      _NullableType(:final base) => base.substitute(environment).nullable,
      FutureOrType(:final argument) => ValueType.futureOr(
        argument.substitute(environment),
      ),
      final ClassType type =>
        type.typeArguments.isEmpty
            ? type
            : type.declaration.instantiate(
                type.typeArguments.map((t) => t.substitute(environment)),
              ),
      CellType(:final content, :final isLate, :final isFinal) => CellType(
        content.substitute(environment),
        isLate: isLate,
        isFinal: isFinal,
      ),
      final RecordType type => RecordType(
        type.fields
            .take(type.positionalCount)
            .map((t) => t.substitute(environment)),
        {
          for (final e in type.slots.entries.skip(type.positionalCount))
            e.key: type.fields[e.value].substitute(environment),
        },
      ),
      final FunctionType type =>
        type.freeTypeParameters.any(environment.containsKey)
            ? type.rebind(environment)
            : type,
      _ => this,
    };
  }

  /// Checks whether these class variables require a runtime variance check.
  ///
  /// Variables in nested function bounds require a check in either variance.
  /// Set [forResult] for a field or return type instead of a parameter type.
  bool requiresCovariantCheck(
    Set<TypeParameterType> parameters, {
    bool forResult = false,
  }) {
    bool visit(ValueType type, Set<TypeParameterType> scope, bool positive) {
      if (type is FunctionType) {
        final free = scope.difference(type.typeParameters.toSet());
        return type.typeParameters.any(
              (p) => p.bound.freeTypeParameters.any(free.contains),
            ) ||
            visit(type.result, free, positive) ||
            type.parameters.any((t) => visit(t, free, !positive));
      }
      return switch (type) {
        TypeParameterType() => positive && scope.contains(type),
        PromotedTypeParameterType(:final parameter, :final bound) =>
          positive && scope.contains(parameter) ||
              visit(bound, scope, positive),
        NonNullableTypeParameterType(:final parameter) =>
          positive && scope.contains(parameter),
        _NullableType(:final base) => visit(base, scope, positive),
        FutureOrType(:final argument) => visit(argument, scope, positive),
        ClassType() => type.typeArguments.any((t) => visit(t, scope, positive)),
        RecordType() => type.fields.any((t) => visit(t, scope, positive)),
        _ => false,
      };
    }

    return visit(this, parameters, !forResult);
  }

  /// Free lexical type-variable identities mentioned by this type expression.
  Iterable<TypeParameterType> get freeTypeParameters =>
      typeDeclarationsIn(this).whereType<TypeParameterType>();

  /// The Dart dynamic top type, distinct from nullable Object.
  static const DynamicType dynamicType = DynamicType();

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

  /// The runtime value of a reified Dart type.
  static const ClassType typeType = ClassType._core('Type', object, true);

  /// The common supertype of all Dart record shapes.
  static const ClassType record = ClassType._core('Record', object, true);

  /// The supertype of all function values.
  static const ClassType function = ClassType._core('Function', object, true);

  /// The canonical Future protocol, also used by the FutureOr type algebra.
  static final ClassType future = ClassType(
    Uri.parse('dart:async'),
    'Future',
    isAbstract: true,
    typeParameters: [
      TypeParameterType('T0')
        ..initializeBound(object.nullable)
        ..initializeDefaultType(dynamicType),
    ],
  );

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

  /// The error raised when runtime dispatch cannot accept an invocation.
  static const ClassType noSuchMethodError = ClassType._core(
    'NoSuchMethodError',
    error,
    false,
  );

  /// The error raised when a core protocol rejects an argument.
  static const ClassType argumentError = ClassType._core(
    'ArgumentError',
    error,
    false,
  );

  /// The error raised when an operation is invalid in the current state.
  static const ClassType stateError = ClassType._core(
    'StateError',
    error,
    false,
  );

  /// The error raised by an operation unsupported by an immutable value.
  static const ClassType unsupportedError = ClassType._core(
    'UnsupportedError',
    error,
    false,
  );

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

  /// The normalized union of [argument] and `Future<argument>`.
  factory futureOr(ValueType argument) {
    if (!isDartType(argument)) {
      throw ArgumentError('FutureOr requires a Dart value type.');
    }
    if (argument == never) return future.instantiate([never]);
    if (argument == nullType) return future.instantiate([nullType]).nullable;
    if (argument is DynamicType ||
        argument == voidType ||
        argument == object ||
        argument == object.nullable) {
      return argument;
    }
    return FutureOrType._(argument);
  }

  /// Whether a runtime inhabitant may be null, distinct from accepting a null assignment.
  bool get mayBeNull => _mayBeNull(null);

  bool _mayBeNull(Set<TypeParameterType>? active) {
    if (this case final TypeParameterType parameter) {
      active ??= {};
      // A recursive bound such as X extends FutureOr<X> may admit Null.
      if (!active.add(parameter)) return true;
      try {
        return parameter.bound._mayBeNull(active);
      } finally {
        active.remove(parameter);
      }
    }
    return switch (this) {
      PromotedTypeParameterType(
        :final parameter,
        :final bound,
        :final isNonNullable,
      ) =>
        !isNonNullable &&
            parameter._mayBeNull(active) &&
            bound._mayBeNull(active),
      FutureOrType(:final argument) => argument._mayBeNull(active),
      _NullableType() || DynamicType() => true,
      _ => this == nullType || this == voidType,
    };
  }

  /// The union of this type and `Null`.
  ValueType get nullable {
    if (this == never) return nullType;
    return accepts(nullType) ? this : _NullableType(this);
  }

  /// The type inside a nullable union, or `null` when there is no such wrapper.
  ValueType? get nullableBase => null;

  /// The static type after Dart's postfix null assertion.
  ValueType get nonNullable => this == nullType ? never : this;

  /// Whether Dart equality on this receiver can only use a core scalar implementation.
  bool get hasScalarEquality {
    final base = nonNullable;
    return number.accepts(base) || base == boolean || base == string;
  }

  /// Whether an operand of [type] can be passed here without a conversion.
  bool accepts(ValueType type) => _accepts(type, null);

  bool _accepts(ValueType type, Set<(ValueType, ValueType)>? active) {
    if (this is CellType || type is CellType) return this == type;
    if (this == type ||
        type == never ||
        this == voidType ||
        this is DynamicType) {
      return true;
    }
    // A promoted variable satisfies both its lexical type and its promoted
    // bound. Keep the target conjunction before projecting either source side.
    if (this case PromotedTypeParameterType(
      :final parameter,
      :final bound,
      :final isNonNullable,
    )) {
      return (!isNonNullable || !type.mayBeNull) &&
          parameter._accepts(type, active) &&
          bound._accepts(type, active);
    }
    if (this case NonNullableTypeParameterType(:final parameter)) {
      return !type.mayBeNull && parameter._accepts(type, active);
    }
    if (type case PromotedTypeParameterType(:final parameter, :final bound)) {
      final nonNullable = !type.mayBeNull;
      return nonNullable && this == object ||
          _accepts(nonNullable ? parameter.nonNullable : parameter, active) ||
          _accepts(nonNullable ? bound.nonNullable : bound, active);
    }
    // Split source unions first: their arms may use different target arms.
    if (type is FutureOrType) {
      return _accepts(type.argument, active) &&
          _accepts(type.futureType, active);
    }
    if (type is _NullableType) {
      return _accepts(nullType, active) && _accepts(type.base, active);
    }
    if (this case FutureOrType(:final argument, :final futureType)) {
      return argument._accepts(type, active) ||
          futureType._accepts(type, active) ||
          switch (type) {
            TypeParameterType() => _acceptsBound(type, active),
            NonNullableTypeParameterType(:final parameter) => _acceptsBound(
              parameter,
              active,
              nonNullable: true,
            ),
            _ => false,
          };
    }
    if (this is TypeParameterType) {
      if (type is NonNullableTypeParameterType) {
        return identical(type.parameter, this) ||
            _acceptsBound(type.parameter, active, nonNullable: true);
      }
      return type is TypeParameterType && _acceptsBound(type, active);
    }
    if (this case _NullableType(:final nonNullable)) {
      return type == nullType ||
          nonNullable == object ||
          nonNullable._accepts(type.nonNullable, active);
    }
    if (type is NonNullableTypeParameterType) {
      return this == object ||
          _acceptsBound(type.parameter, active, nonNullable: true);
    }
    if (type is TypeParameterType) {
      // Only the bound is known about an arbitrary value of a type variable.
      return _acceptsBound(type, active);
    }
    if (type is FunctionType) {
      final target = this;
      return target is FunctionType
          ? target._acceptsFunction(type, active)
          : target == function || target == object;
    }
    if (type is RecordType) {
      final target = this;
      if (target is! RecordType) return target == record || target == object;
      return target.sameShape(type) &&
          target.fields.indexed.every(
            (p) => p.$2._accepts(type.fields[p.$1], active),
          );
    }
    return this is ClassType &&
        type is ClassType &&
        type._inherits(this as ClassType, active);
  }

  bool _acceptsBound(
    TypeParameterType parameter,
    Set<(ValueType, ValueType)>? active, {
    bool nonNullable = false,
  }) {
    active ??= {};
    final obligation = (this, nonNullable ? parameter.nonNullable : parameter);
    if (!active.add(obligation)) return false;
    try {
      final bound = nonNullable ? parameter.bound.nonNullable : parameter.bound;
      return _accepts(bound, active);
    } finally {
      active.remove(obligation);
    }
  }
}

/// The union `Future<T> | T`, kept distinct from either nominal arm.
///
/// Construct through [ValueType.futureOr] so special arguments normalize.
/// Null assertion removes only an outer `?`, not nullability inside [argument].
final class FutureOrType._(final ValueType argument) extends ValueType {
  /// The Future arm with the same, unflattened type argument.
  late final ClassType futureType = ValueType.future.instantiate([argument]);

  @override
  String get dartName => 'FutureOr<${argument.dartName}>';
  @override
  bool operator ==(Object other) =>
      other is FutureOrType && argument == other.argument;
  @override
  int get hashCode => Object.hash(FutureOrType, argument);
}

/// A top type whose operations require runtime dispatch or checked conversion.
final class const DynamicType() extends ValueType {
  @override
  String get dartName => 'dynamic';
  @override
  ValueType get nullable => this;
  @override
  ValueType get nonNullable => this;
  @override
  bool operator ==(Object other) => other is DynamicType;
  @override
  int get hashCode => 'dynamic'.hashCode;
}

/// An internal reference to a captured variable with invariant [content] type.
final class CellType(
  /// The Dart type stored in the shared variable.
  final ValueType content, {

  /// Whether unbound reads initialize lazily or raise a late error.
  final bool isLate = false,

  /// Whether a late cell permits only one successful binding.
  final bool isFinal = false,
}) extends ValueType {
  this {
    if (isFinal && !isLate) {
      throw ArgumentError('Only late capture storage has runtime finality.');
    }
    if (content is CellType) {
      throw ArgumentError('A captured slot must hold a Dart value.');
    }
  }

  @override
  ValueType get nullable =>
      throw UnsupportedError('Capture storage cannot be nullable.');
  @override
  String get dartName =>
      '${isLate ? 'late ' : ''}${isFinal ? 'final ' : ''}cell<${content.dartName}>';
  @override
  bool operator ==(Object other) =>
      other is CellType &&
      other.content == content &&
      other.isLate == isLate &&
      other.isFinal == isFinal;
  @override
  int get hashCode => isLate
      ? Object.hash(CellType, content, isLate, isFinal)
      : Object.hash(CellType, content);
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
  /// Copies a function signature with fresh binders and substituted free types.
  ///
  /// [defaultTemplates] optionally supplies compiler-computed runtime defaults;
  /// their free types are substituted without changing the source binders.
  FunctionType rebind(
    Map<TypeParameterType, ValueType> environment, {
    List<ValueType>? defaultTemplates,
  }) {
    if (defaultTemplates != null &&
        defaultTemplates.length != typeParameters.length) {
      throw ArgumentError('Mismatched function type defaults.');
    }
    final fresh = [for (final p in typeParameters) TypeParameterType(p.name)];
    final scoped = <TypeParameterType, ValueType>{
      ...environment,
      for (final (i, p) in typeParameters.indexed) p: fresh[i],
    };
    for (final (i, p) in fresh.indexed) {
      p.initializeBound(typeParameters[i].bound.substitute(scoped));
    }
    for (final (i, p) in fresh.indexed) {
      if ((defaultTemplates?[i] ?? typeParameters[i].defaultType)
          case final defaultType?) {
        p.initializeDefaultType(defaultType.substitute(scoped));
      }
    }
    final body = _bodyWith(scoped);
    return FunctionType(
      body.result,
      body.parameters,
      typeParameters: fresh,
      optionalPositional: body.optionalPositional,
      namedParameters: body.namedParameters,
    );
  }

  /// The number of trailing positional parameters with defaults.
  int get optionalPositional => positionalCount - requiredPositional;

  /// Each named parameter in declaration order and whether it is required.
  Map<String, bool> get namedParameters => Map.unmodifiable(
    named.map((name, parameter) => MapEntry(name, parameter.required)),
  );

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

  /// Recorded default arguments in binder order, without inferring missing data.
  ///
  /// Defaults are execution metadata, not part of this function's type identity.
  /// A generic signature may omit them until default instantiation is requested.
  List<ValueType> get defaultTypeArguments => List.unmodifiable([
    for (final parameter in typeParameters)
      parameter.defaultType ??
          (throw StateError(
            'Missing default type metadata for ${parameter.name}.',
          )),
  ]);

  /// Applies the recorded defaults using the ordinary bound checks.
  FunctionType instantiateToBounds() => instantiate(defaultTypeArguments);

  /// Applies every function type argument simultaneously and checks its bound.
  FunctionType instantiate(Iterable<ValueType> arguments) {
    final args = List<ValueType>.unmodifiable(arguments);
    if (args.length != typeParameters.length ||
        args.any((t) => t is CellType)) {
      throw ArgumentError('Invalid function type arguments.');
    }
    if (typeParameters.isEmpty) return this;
    final environment = {
      for (final (i, parameter) in typeParameters.indexed) parameter: args[i],
    };
    for (final (i, parameter) in typeParameters.indexed) {
      if (!parameter.bound.substitute(environment).accepts(args[i])) {
        throw ArgumentError(
          'Type argument does not satisfy ${parameter.name} bound.',
        );
      }
    }
    return _bodyWith(environment);
  }

  FunctionType _bodyWith(Map<TypeParameterType, ValueType> environment) =>
      FunctionType(
        result.substitute(environment),
        parameters.map((t) => t.substitute(environment)),
        optionalPositional: optionalPositional,
        namedParameters: namedParameters,
      );

  Map<TypeParameterType, ValueType>? _relate(
    FunctionType other, {
    bool exactBounds = true,
    Set<(ValueType, ValueType)>? active,
  }) {
    if (typeParameters.length != other.typeParameters.length) return null;
    final environment = <TypeParameterType, ValueType>{
      for (final (i, parameter) in other.typeParameters.indexed)
        parameter: typeParameters[i],
    };
    for (final (i, parameter) in typeParameters.indexed) {
      final bound = other.typeParameters[i].bound.substitute(environment);
      if (exactBounds
          ? parameter.bound != bound
          : !parameter.bound._accepts(bound, active) ||
                !bound._accepts(parameter.bound, active)) {
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

  bool _acceptsFunction(
    FunctionType actual,
    Set<(ValueType, ValueType)>? active,
  ) {
    final environment = _relate(actual, exactBounds: false, active: active);
    if (environment == null) return false;
    if (typeParameters.isNotEmpty) {
      return _bodyWith(const {})
          ._acceptsFunction(actual._bodyWith(environment), active);
    }
    if (!result._accepts(actual.result, active) ||
        actual.requiredPositional > requiredPositional ||
        actual.positionalCount < positionalCount) {
      return false;
    }
    for (var i = 0; i < positionalCount; i++) {
      if (!actual.parameters[i]._accepts(parameters[i], active)) return false;
    }
    for (final MapEntry(:key, value: p) in named.entries) {
      final q = actual.named[key];
      if (q == null ||
          !actual.parameters[q.slot]._accepts(parameters[p.slot], active)) {
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
  final List<ValueType>? _arguments,
  final ClassType? _declaration,
  final _ClassHierarchy? _hierarchy, {
  final bool _isCore = false,
  final NativeTypeRef? _nativeType,
}) extends ValueType {
  new(
    Uri? library,
    String name, {
    ClassType superclass = ValueType.object,
    Iterable<ClassType> interfaces = const [],
    bool isAbstract = false,
    NativeTypeRef? nativeType,
    Iterable<TypeParameterType> typeParameters = const [],
  }) : this._(
         library,
         name,
         superclass,
         .unmodifiable(interfaces),
         isAbstract,
         .unmodifiable(typeParameters),
         null,
         null,
         null,
         nativeType: nativeType,
       );

  const new _core(String name, ClassType? parent, bool isAbstract)
    : this._(
        null,
        name,
        parent,
        const [],
        isAbstract,
        const [],
        null,
        null,
        null,
        isCore: true,
      );

  /// Creates a declaration whose hierarchy can be initialized before verification.
  new declare(
    Uri? library,
    String name, {
    Iterable<TypeParameterType> typeParameters = const [],
    bool isAbstract = false,
    NativeTypeRef? nativeType,
  }) : this._(
         library,
         name,
         null,
         const [],
         isAbstract,
         .unmodifiable(typeParameters),
         null,
         null,
         _ClassHierarchy(),
         nativeType: nativeType,
       );

  /// Sets the hierarchy once, before a verified graph or program uses this type.
  void initializeHierarchy({
    ClassType superclass = ValueType.object,
    Iterable<ClassType> interfaces = const [],
  }) {
    final hierarchy = declaration._hierarchy;
    if (!identical(this, declaration) ||
        hierarchy == null ||
        hierarchy.initialized ||
        hierarchy.sealed) {
      throw StateError('Class hierarchy already initialized or sealed.');
    }
    final implemented = List<ClassType>.unmodifiable(interfaces);
    if (superclass.asInstanceOf(this) != null ||
        implemented.any((parent) => parent.asInstanceOf(this) != null)) {
      throw ArgumentError('Cyclic class hierarchy for $name.');
    }
    hierarchy.interfaces = implemented;
    hierarchy.superclass = superclass;
    hierarchy.initialized = true;
  }

  /// Native storage described by this declaration, distinct from managed layout.
  NativeTypeRef? get nativeType => declaration._nativeType;

  static final _coreLibrary = Uri.parse('dart:core');

  /// The applied arguments, or the declaration's own type parameters.
  List<ValueType> get typeArguments => _arguments ?? typeParameters;

  /// The source library, or null for a generated declaration.
  Uri? get library => _isCore ? _coreLibrary : _library;
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
        : parent.substitute(typeEnvironment) as ClassType;
  }

  List<ClassType> get interfaces => [
    for (final type
        in (declaration._hierarchy?.interfaces ?? declaration._interfaces))
      type.substitute(typeEnvironment) as ClassType,
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
      final bound = parameter.bound.substitute(typeEnvironment);
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

  bool _inherits(ClassType target, Set<(ValueType, ValueType)>? active) {
    final view = asInstanceOf(target);
    return view != null &&
        target.typeArguments.indexed.every(
          (e) => e.$2._accepts(view.typeArguments[e.$1], active),
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
  bool sealed = false;
  ClassType? superclass;
  List<ClassType> interfaces = const [];
}

/// A lexically scoped type variable. Equal names do not imply equal identities.
final class TypeParameterType(final String name) extends ValueType {
  bool _sealed = false;
  ValueType? _bound;
  ValueType get bound =>
      _bound ?? (throw StateError('Uninitialized type parameter bound.'));
  void initializeBound(ValueType type) {
    if (_sealed || _bound != null || type is CellType) {
      throw StateError('Invalid type parameter bound initialization.');
    }
    _bound = type;
  }

  ValueType? _defaultType;

  /// The compiler-computed default template, when metadata is available.
  ValueType? get defaultType => _defaultType;

  /// Records a default once, before a verified graph or program uses this binder.
  ///
  /// Recursive bounds may have defaults that are invalid only when applied.
  void initializeDefaultType(ValueType type) {
    if (_sealed || _defaultType != null || type is CellType) {
      throw StateError('Invalid type parameter default initialization.');
    }
    _defaultType = type;
  }

  @override
  String get dartName => name;
  @override
  ValueType get nonNullable => NonNullableTypeParameterType(this);
}

// Finish recursive declarations before publishing checked graphs or programs.
void sealTypes(Iterable<ValueType> roots) {
  final types = Set<ValueType>.identity();
  void visit(ValueType type) {
    if (!types.add(type)) return;
    switch (type) {
      case TypeParameterType():
        visit(type.bound);
        if (type.defaultType case final value?) visit(value);
      case ClassType():
        final declaration = type.declaration;
        if (!identical(type, declaration)) visit(declaration);
        type.typeArguments.forEach(visit);
        final parent =
            declaration._hierarchy?.superclass ?? declaration._superclass;
        if (parent != null) visit(parent);
        (declaration._hierarchy?.interfaces ?? declaration._interfaces).forEach(
          visit,
        );
      case FunctionType():
        type.typeParameters.forEach(visit);
        visit(type.result);
        type.parameters.forEach(visit);
      case RecordType():
        type.fields.forEach(visit);
      case PromotedTypeParameterType(:final parameter, :final bound):
        visit(parameter);
        visit(bound);
      case NonNullableTypeParameterType(:final parameter):
        visit(parameter);
      case _NullableType(:final base):
        visit(base);
      case FutureOrType(:final argument):
        visit(ValueType.future);
        visit(argument);
      case CellType(:final content):
        visit(content);
      default:
        break;
    }
  }

  roots.forEach(visit);
  for (final type in types) {
    if (type is TypeParameterType) type._sealed = true;
    if (type is ClassType) type._hierarchy?.sealed = true;
  }
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

/// A flow-promoted lexical variable `parameter & bound`.
///
/// The bound supplies additional static evidence, not a new runtime type.
/// Inference and runtime type arguments retain the original lexical parameter.
final class PromotedTypeParameterType(
  final TypeParameterType parameter,
  final ValueType bound, {

  /// An additional value-level non-null fact established by a null assertion.
  final bool isNonNullable = false,
}) extends ValueType {
  this {
    if (!isDartType(bound)) {
      throw ArgumentError('A promoted bound must be a Dart value type.');
    }
  }

  @override
  String get dartName =>
      '${parameter.dartName} & ${bound.dartName}${isNonNullable ? ' & Object' : ''}';
  @override
  ValueType get nonNullable => !mayBeNull
      ? this
      : PromotedTypeParameterType(parameter, bound, isNonNullable: true);
  @override
  bool operator ==(Object other) =>
      other is PromotedTypeParameterType &&
      identical(parameter, other.parameter) &&
      bound == other.bound &&
      isNonNullable == other.isNonNullable;
  @override
  int get hashCode =>
      Object.hash(PromotedTypeParameterType, parameter, bound, isNonNullable);
}

final class const _SpecialType(@override final String dartName)
    extends ValueType;

final class const _NullableType(final ValueType base) extends ValueType {
  @override
  ValueType get nullableBase => base;
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

/// Nominal declarations and free type variables referenced by a type expression.
Iterable<ValueType> typeDeclarationsIn(ValueType type) sync* {
  switch (type) {
    case TypeParameterType():
      yield type;
    case PromotedTypeParameterType(:final parameter, :final bound):
      yield parameter;
      yield* typeDeclarationsIn(bound);
    case NonNullableTypeParameterType(:final parameter):
      yield parameter;
    case _NullableType(:final base):
      yield* typeDeclarationsIn(base);
    case FutureOrType(:final argument):
      yield ValueType.future;
      yield* typeDeclarationsIn(argument);
    case ClassType():
      yield type.declaration;
      for (final argument in type.typeArguments) {
        yield* typeDeclarationsIn(argument);
      }
    case RecordType():
      for (final field in type.fields) {
        yield* typeDeclarationsIn(field);
      }
    case FunctionType():
      final bound = type.typeParameters.toSet();
      for (final nested in [
        type.result,
        ...type.parameters,
        ...type.typeParameters.map((p) => p.bound),
        for (final parameter in type.typeParameters) ?parameter.defaultType,
      ]) {
        yield* typeDeclarationsIn(nested).where((t) => !bound.contains(t));
      }
    case CellType(:final content):
      yield* typeDeclarationsIn(content);
    default:
      break;
  }
}

int _typeHash(ValueType type, Map<TypeParameterType, int> scope) {
  return switch (type) {
    TypeParameterType() =>
      scope.containsKey(type)
          ? Object.hash(TypeParameterType, scope[type])
          : identityHashCode(type),
    PromotedTypeParameterType(
      :final parameter,
      :final bound,
      :final isNonNullable,
    ) =>
      Object.hash(
        PromotedTypeParameterType,
        _typeHash(parameter, scope),
        _typeHash(bound, scope),
        isNonNullable,
      ),
    NonNullableTypeParameterType(:final parameter) => Object.hash(
      NonNullableTypeParameterType,
      _typeHash(parameter, scope),
    ),
    _NullableType(:final base) => Object.hash(
      _NullableType,
      _typeHash(base, scope),
    ),
    FutureOrType(:final argument) => Object.hash(
      FutureOrType,
      _typeHash(argument, scope),
    ),
    ClassType() => Object.hash(
      identityHashCode(type.declaration),
      Object.hashAll(type.typeArguments.map((t) => _typeHash(t, scope))),
    ),
    CellType(:final content, :final isLate, :final isFinal) =>
      isLate
          ? Object.hash(CellType, _typeHash(content, scope), isLate, isFinal)
          : Object.hash(CellType, _typeHash(content, scope)),
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

/// Whether a type expression consists only of source-level Dart types.
bool isDartType(ValueType type) => switch (type) {
  CellType() => false,
  _NullableType(:final base) => isDartType(base),
  FutureOrType(:final argument) => isDartType(argument),
  ClassType() => type.typeArguments.every(isDartType),
  RecordType() => type.fields.every(isDartType),
  FunctionType() =>
    isDartType(type.result) &&
        type.parameters.every(isDartType) &&
        type.typeParameters.every((p) => isDartType(p.bound)),
  _ => true,
};
