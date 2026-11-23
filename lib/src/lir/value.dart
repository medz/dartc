/// The four kinds of machine value.
enum LirType() {
  /// A 64-bit integer; a boolean is 0 or 1.
  i64,

  /// An IEEE 754 double.
  f64,

  /// A reference traced by the garbage collector, possibly null.
  ref,

  /// A native address the garbage collector never inspects.
  ptr,
}

/// The inputs and the optional result of a callable.
final class LirSignature(
  Iterable<LirType> parameters, [
  final LirType? result,
]) {
  final List<LirType> parameters = .unmodifiable(parameters);

  @override
  bool operator ==(Object other) =>
      other is LirSignature &&
      other.result == result &&
      other.parameters.length == parameters.length &&
      other.parameters.indexed.every((e) => e.$2 == parameters[e.$1]);

  @override
  int get hashCode => Object.hash(result, Object.hashAll(parameters));

  @override
  String toString() =>
      '(${parameters.map((type) => type.name).join(', ')})'
      '${result == null ? '' : ' -> ${result!.name}'}';
}

/// Something usable as an operand, defined exactly once.
abstract class LirValue() {
  /// The value's type; null for an instruction without a result.
  LirType? get type;
}

/// A value received by a block from each edge that enters it.
final class LirParameter(@override final LirType type) extends LirValue;
