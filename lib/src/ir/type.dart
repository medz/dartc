/// A Dart type carried by an SSA value, a block parameter or a function signature.
sealed class const ValueType() {
  /// The non-nullable `Object` type.
  static const ValueType object = _CoreType('Object');

  /// The common supertype of `int` and `double`.
  static const ValueType number = _CoreType('num', object);

  /// The non-nullable `int` type.
  static const ValueType integer = _CoreType('int', number);

  /// The non-nullable `double` type.
  static const ValueType floating = _CoreType('double', number);

  /// The non-nullable `bool` type.
  static const ValueType boolean = _CoreType('bool', object);

  /// The non-nullable `String` type.
  static const ValueType string = _CoreType('String', object);

  /// The common supertype of all Dart record shapes.
  static const ValueType record = _CoreType('Record', object);

  /// The Dart trace paired with a caught exception.
  static const ValueType stackTrace = _CoreType('StackTrace', object);

  /// The superclass of Dart runtime errors.
  static const ValueType error = _CoreType('Error', object);

  /// The error raised by failed runtime type checks.
  static const ValueType typeError = _CoreType('TypeError', error);

  /// The type whose only value is `null`.
  static const ValueType nullType = _CoreType('Null');

  /// The type with no values.
  static const ValueType never = _CoreType('Never');

  /// The top type whose uses Dart restricts statically.
  static const ValueType voidType = _CoreType('void');

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
    return type is _CoreType && type.parent != null && accepts(type.parent!);
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

final class const _CoreType(
  @override final String dartName, [
  final ValueType? parent,
]) extends ValueType;

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
