/// The Dart types a value can have.
enum HirType(final String dartName) {
  integer('int'),
  float('double'),
  boolean('bool'),
}

/// Something usable as an operand, defined exactly once.
abstract class HirValue() {
  /// The value's type; null for an operation without a result.
  HirType? get type;
}

/// A value received by a block from each edge that enters it.
final class HirParameter(@override final HirType type) extends HirValue;

/// Something that can be called, identified by itself rather than its name.
abstract class HirCallable() {
  String get name;
  List<HirType> get parameters;

  /// The type of the result, if there is one.
  HirType? get result;
}
