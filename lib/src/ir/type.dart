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

  /// The type whose only value is `null`.
  static const ValueType nullType = _SpecialType('Null');

  /// The type with no values.
  static const ValueType never = _SpecialType('Never');

  /// The top type whose uses Dart restricts statically.
  static const ValueType voidType = _SpecialType('void');

  /// The spelling used in a Dart type annotation.
  String get dartName;

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
    if (identical(this, type) || type == never || this == voidType) return true;
    if (this case _NullableType(:final nonNullable)) {
      return type == nullType ||
          nonNullable == object ||
          nonNullable.accepts(type.nonNullable);
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

/// A non-generic Dart function type with positional and named parameter slots.
final class FunctionType._(
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
    return ._(
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionType &&
          result == other.result &&
          positionalCount == other.positionalCount &&
          requiredPositional == other.requiredPositional &&
          named.length == other.named.length &&
          parameters
              .take(positionalCount)
              .indexed
              .every((p) => p.$2 == other.parameters[p.$1]) &&
          named.entries.every((e) {
            final p = other.named[e.key];
            return p != null &&
                p.required == e.value.required &&
                parameters[e.value.slot] == other.parameters[p.slot];
          });

  @override
  int get hashCode => Object.hash(
    result,
    requiredPositional,
    Object.hashAll(parameters.take(positionalCount)),
    Object.hashAllUnordered(
      named.entries.map(
        (e) => Object.hash(e.key, e.value.required, parameters[e.value.slot]),
      ),
    ),
  );

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
    return '${result.dartName} Function(${parts.join(', ')})';
  }
}

/// A nominal Dart class shared by its declarations, value types and runtime tests.
final class const ClassType._(
  final Uri? _library,
  @override final String dartName,

  /// The immediate superclass, absent only for `Object`.
  final ClassType? superclass,

  /// The directly implemented interfaces, excluding [superclass].
  final List<ClassType> interfaces,

  /// Whether direct allocation of this class is forbidden.
  final bool isAbstract,
) extends ValueType {
  /// Creates a class identity with [superclass] and directly implemented [interfaces].
  new(
    Uri library,
    String name, {
    ClassType superclass = ValueType.object,
    Iterable<ClassType> interfaces = const [],
    bool isAbstract = false,
  }) : this._(library, name, superclass, .unmodifiable(interfaces), isAbstract);

  const new _core(String name, ClassType? parent, bool isAbstract)
    : this._(null, name, parent, const [], isAbstract);

  static final _coreLibrary = Uri.parse('dart:core');

  /// The URI of the declaring library.
  Uri get library => _library ?? _coreLibrary;

  bool _inherits(ClassType target, [Set<ClassType>? visited]) {
    for (ClassType? type = this; type != null; type = type.superclass) {
      if (identical(type, target)) return true;
      if (type.interfaces.isEmpty) continue;
      visited ??= {};
      if (!visited.add(type)) return false;
      for (final interface in type.interfaces) {
        if (interface._inherits(target, visited)) return true;
      }
    }
    return false;
  }
}

final class const _SpecialType(@override final String dartName)
    extends ValueType;

final class const _NullableType(@override final ValueType nonNullable)
    extends ValueType {
  @override
  String get dartName => '${nonNullable.dartName}?';

  @override
  bool operator ==(Object other) =>
      other is _NullableType && nonNullable == other.nonNullable;

  @override
  int get hashCode => Object.hash(_NullableType, nonNullable);
}
