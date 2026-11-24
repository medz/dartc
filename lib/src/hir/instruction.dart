import 'class.dart';
import 'global.dart';
import 'machine.dart';
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

/// The null reference.
final class HirNull() extends HirInstruction {
  @override
  HirType get type => .reference;
  @override
  List<HirValue> get inputs => const [];
}

/// An operation that may throw.
sealed class HirCalling() extends HirInstruction;

/// An object of [target] whose references are null and numbers are unset.
final class HirNew(final HirClass target) extends HirCalling {
  @override
  HirType get type => .reference;
  @override
  List<HirValue> get inputs => const [];
}

/// An object of [target], whose only field has [value].
///
/// It never changes. An integer may be in the reference itself.
final class HirBox(final HirClass target, final HirValue value)
    extends HirCalling {
  @override
  HirType get type => .reference;
  @override
  List<HirValue> get inputs => [value];
}

/// What [object], which is never null and that [HirBox] gives, has in [field].
final class HirUnbox(final HirField field, final HirValue object)
    extends HirInstruction {
  @override
  HirType get type => field.type;
  @override
  List<HirValue> get inputs => [object];
}

/// An array of [target] with [length] elements, which is not negative.
///
/// They are null or 0.
final class HirNewArray(final HirClass target, final HirValue length)
    extends HirCalling {
  @override
  HirType get type => .reference;
  @override
  List<HirValue> get inputs => [length];
}

/// How many elements [array] has.
final class HirLength(final HirValue array) extends HirInstruction {
  @override
  HirType get type => .integer;
  @override
  List<HirValue> get inputs => [array];
}

/// Reads an element of [array] at [index], which is one of its elements or,
/// among bytes, the first of those that [element] takes.
final class HirLoadElement(
  final HirElement element,
  final HirValue array,
  final HirValue index,
) extends HirInstruction {
  @override
  HirType get type => element.type;
  @override
  List<HirValue> get inputs => [array, index];
}

/// Writes [value] like [HirLoadElement] reads it.
final class HirStoreElement(
  final HirElement element,
  final HirValue array,
  final HirValue index,
  final HirValue value,
) extends HirInstruction {
  @override
  HirType? get type => null;
  @override
  List<HirValue> get inputs => [array, index, value];
}

/// The number of [target], or -1 if it has no objects.
final class HirClassNumber(final HirClass target) extends HirInstruction {
  @override
  HirType get type => .integer;
  @override
  List<HirValue> get inputs => const [];
}

/// The address of the function of C called [name].
final class HirNativeFunction(final String name) extends HirInstruction {
  @override
  HirType get type => .integer;
  @override
  List<HirValue> get inputs => const [];
}

/// The object that [object] is.
final class HirStatic(final HirConstObject object) extends HirInstruction {
  @override
  HirType get type => .reference;
  @override
  List<HirValue> get inputs => const [];
}

final class HirLoadGlobal(final HirGlobal global) extends HirInstruction {
  @override
  HirType get type => global.type;
  @override
  List<HirValue> get inputs => const [];
}

final class HirStoreGlobal(final HirGlobal global, final HirValue value)
    extends HirInstruction {
  @override
  HirType? get type => null;
  @override
  List<HirValue> get inputs => [value];
}

/// Performs [op] for the runtime.
final class HirMachine(final HirMachineOp op, Iterable<HirValue> arguments)
    extends HirInstruction {
  final List<HirValue> arguments = .unmodifiable(arguments);
  @override
  HirType? get type => op.result;
  @override
  List<HirValue> get inputs => arguments;
}

/// Reads [field] of [object], which is never null.
final class HirLoad(final HirField field, final HirValue object)
    extends HirInstruction {
  @override
  HirType get type => field.type;
  @override
  List<HirValue> get inputs => [object];
}

/// Writes [value] to [field] of [object], which is never null.
final class HirStore(
  final HirField field,
  final HirValue object,
  final HirValue value,
) extends HirInstruction {
  @override
  HirType? get type => null;
  @override
  List<HirValue> get inputs => [object, value];
}

/// Calls what the class of [receiver], which is never null, has for [selector].
final class HirVirtualCall(
  final HirSelector selector,
  final HirValue receiver,
  Iterable<HirValue> arguments,
) extends HirCalling {
  final List<HirValue> arguments = .unmodifiable(arguments);
  @override
  HirType? get type => selector.result;
  @override
  List<HirValue> get inputs => [receiver, ...arguments];
}

/// The `int` operators.
///
/// Division and remainder need a right operand other than 0, and shifts one
/// that is not negative, so none of them throws.
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

/// The operators with one operand.
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

  /// Truncates a finite `double` to the nearest `int` there is.
  floatToInt('int ', .float, .integer),

  /// The same 64 bits.
  floatBits('bits ', .float, .integer),
  bitsFloat('of bits ', .integer, .float),
  squareRoot('sqrt ', .float, .float),
}

final class HirUnary(final HirUnaryOperator operator, final HirValue operand)
    extends HirInstruction {
  @override
  HirType get type => operator.result;
  @override
  List<HirValue> get inputs => [operand];
}

/// The comparisons; `bool` operands and references, which are compared by
/// identity, admit only the first two.
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

/// Whether the class of [object], which is never null, passes [test].
final class HirIsInstance(final HirTypeTest test, final HirValue object)
    extends HirInstruction {
  @override
  HirType get type => .boolean;
  @override
  List<HirValue> get inputs => [object];
}

/// Calls [target] with one argument for each of its parameters.
final class HirCall(final HirCallable target, Iterable<HirValue> arguments)
    extends HirCalling {
  final List<HirValue> arguments = .unmodifiable(arguments);
  @override
  HirType? get type => target.result;
  @override
  List<HirValue> get inputs => arguments;
}
