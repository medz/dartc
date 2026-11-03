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

  /// Whether an operand of [type] can be passed here without a conversion.
  bool accepts(ValueType type) {
    if (this == type || type == never || this == voidType) return true;
    if (this case _NullableType(:final nonNullable)) {
      return type == nullType ||
          nonNullable == object ||
          nonNullable.accepts(type.nonNullable);
    }
    return type is _CoreType && type.parent != null && accepts(type.parent!);
  }
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
