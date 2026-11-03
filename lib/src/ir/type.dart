/// A Dart type carried by an SSA value, a block parameter or a function signature.
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
    if (identical(this, type) || type == never || this == voidType) return true;
    if (this case _NullableType(:final nonNullable)) {
      return type == nullType ||
          nonNullable == object ||
          nonNullable.accepts(type.nonNullable);
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
