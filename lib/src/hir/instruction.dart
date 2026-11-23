import 'value.dart';

/// An operation executed in order inside a block.
sealed class HirInstruction() extends HirValue {
  /// The operands, in evaluation order.
  List<HirValue> get inputs;
}

/// A literal or other constant: an `int`, a `double` or a `bool`.
final class HirConst(final Object value) extends HirInstruction {
  @override
  HirType get type => switch (value) {
    int() => .integer,
    double() => .float,
    bool() => .boolean,
    _ => throw ArgumentError.value(value, 'value'),
  };
  @override
  List<HirValue> get inputs => const [];
}

/// The `int` operators.
///
/// Division and remainder need a constant right operand other than 0, and
/// shifts one that is not negative, so none of them throws.
enum HirIntOperator(final String symbol) {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('~/'),
  modulo('%'),
  and('&'),
  or('|'),
  xor('^'),
  shiftLeft('<<'),
  shiftRight('>>'),
  shiftRightUnsigned('>>>');

  bool get isDivision => this == divide || this == modulo;
  bool get isShift =>
      this == shiftLeft || this == shiftRight || this == shiftRightUnsigned;
}

final class HirIntBinary(
  final HirIntOperator operator,
  final HirValue left,
  final HirValue right,
) extends HirInstruction {
  @override
  HirType get type => .integer;
  @override
  List<HirValue> get inputs => [left, right];
}

/// The `double` operators.
enum HirFloatOperator(final String symbol) {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('/'),
  modulo('%'),
}

final class HirFloatBinary(
  final HirFloatOperator operator,
  final HirValue left,
  final HirValue right,
) extends HirInstruction {
  @override
  HirType get type => .float;
  @override
  List<HirValue> get inputs => [left, right];
}

/// The `bool` operators that evaluate both operands.
enum HirBoolOperator(final String symbol) {
  and('&'),
  or('|'),
  xor('^'),
}

final class HirBoolBinary(
  final HirBoolOperator operator,
  final HirValue left,
  final HirValue right,
) extends HirInstruction {
  @override
  HirType get type => .boolean;
  @override
  List<HirValue> get inputs => [left, right];
}

/// The operators with one operand, all keeping its type but the last.
enum HirUnaryOperator(
  final String symbol,
  final HirType operand,
  final HirType result,
) {
  negateInt('-', .integer, .integer),
  complement('~', .integer, .integer),
  negateFloat('-', .float, .float),
  not('!', .boolean, .boolean),

  /// The nearest `double`.
  intToFloat('double ', .integer, .float),
}

final class HirUnary(final HirUnaryOperator operator, final HirValue operand)
    extends HirInstruction {
  @override
  HirType get type => operator.result;
  @override
  List<HirValue> get inputs => [operand];
}

/// The comparisons; `bool` operands admit only the first two.
enum HirRelation(final String symbol) {
  equal('=='),
  notEqual('!='),
  less('<'),
  lessOrEqual('<='),
  greater('>'),
  greaterOrEqual('>=');

  bool get isEquality => this == equal || this == notEqual;
}

/// Compares two operands of one type.
final class HirCompare(
  final HirRelation relation,
  final HirValue left,
  final HirValue right,
) extends HirInstruction {
  @override
  HirType get type => .boolean;
  @override
  List<HirValue> get inputs => [left, right];
}

/// Writes [text] and a newline to standard output, as `print` does.
final class HirPrint(final String text) extends HirInstruction {
  @override
  HirType? get type => null;
  @override
  List<HirValue> get inputs => const [];
}

/// Calls [target] with one argument for each of its parameters.
final class HirCall(final HirCallable target, Iterable<HirValue> arguments)
    extends HirInstruction {
  final List<HirValue> arguments = .unmodifiable(arguments);
  @override
  HirType? get type => target.result;
  @override
  List<HirValue> get inputs => arguments;
}
