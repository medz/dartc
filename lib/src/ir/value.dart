import 'signature.dart';
import 'type.dart';

/// An operand in static single assignment (SSA) form.
///
/// A use refers to its defining instruction or block parameter by identity.
/// A [Constant] can be used in any block.
sealed class const Value(
  /// The static Dart type before machine representation selection.
  final ValueType type,
);

/// A scalar constant that requires no instruction to produce it.
final class const Constant._(
  /// The Dart value represented by this operand.
  final Object? value,
  super.type,
) extends Value {
  /// Creates an integer literal with the value [value].
  const new integer(int value) : this._(value, .integer);

  /// Creates a boolean literal with the value [value].
  const new boolean(bool value) : this._(value, .boolean);

  /// Creates a double literal, preserving the sign of zero.
  const new floating(double value) : this._(value, .floating);

  /// Creates a string literal from its decoded [value].
  const new string(String value) : this._(value, .string);

  /// Creates the Dart `null` value.
  const new nullValue() : this._(null, .nullType);
}

/// A value supplied on entry to a block by the caller or an incoming jump.
final class BlockParameter._(super.type) extends Value;

/// Allocates a distinct SSA parameter for each entry in [types].
List<BlockParameter> blockParameters(Iterable<ValueType> types) =>
    .unmodifiable(types.map(BlockParameter._));

/// An operation executed at its position in a block's instruction list.
sealed class Instruction(super.type) extends Value {
  /// The SSA operands consumed by the operation.
  Iterable<Value> get inputs;
}

/// A test for the Dart null value which never invokes an equality operator.
final class NullTest(
  /// The already evaluated operand.
  final Value operand, {

  /// Whether the result is true when [operand] is non-null.
  final bool negated = false,
}) extends Instruction {
  this : super(.boolean);

  /// The same operand with its non-null type, valid only on the non-null edge.
  late final NonNullValue nonNull = ._(this);

  @override
  Iterable<Value> get inputs => [operand];
}

/// The non-null operand passed by a branch on [test].
///
/// Only a jump on the non-null side of that branch may use this value as an
/// argument. Its destination reads an ordinary block parameter.
final class NonNullValue._(
  /// The test that establishes this value's type.
  final NullTest test,
) extends Value {
  this : super(test.operand.type.nonNullable);
}

/// A postfix null assertion that throws a Dart type error when [operand] is null.
final class NullCheck(
  /// The value returned unchanged on success.
  final Value operand,
) extends Instruction {
  this : super(operand.type.nonNullable);

  @override
  Iterable<Value> get inputs => [operand];
}

/// A binary operation on two non-nullable Dart integers.
enum IntOperator(
  /// The static type produced by the operation.
  final ValueType result,
) {
  /// Integer addition.
  add(.integer),

  /// Subtraction of the right operand from the left.
  subtract(.integer),

  /// Integer multiplication.
  multiply(.integer),

  /// Whether the left operand is smaller than the right.
  lessThan(.boolean),
}

/// An arithmetic or comparison instruction on two integers.
final class IntBinary(
  /// The operation applied to [left] and [right].
  final IntOperator operator,

  /// The first operand.
  final Value left,

  /// The second operand.
  final Value right,
) extends Instruction {
  /// Creates an instruction with the result type of [operator].
  ///
  /// Throws [ArgumentError] unless both operands have type [ValueType.integer].
  this : super(operator.result) {
    if (left.type != .integer || right.type != .integer) {
      throw ArgumentError('Integer operands required.');
    }
  }

  @override
  Iterable<Value> get inputs => [left, right];
}

/// A call to a statically bound function.
///
/// The call may change state or throw even when its result is unused.
final class DirectCall(
  /// The declaration selected during binding.
  final FunctionTarget target,
  Iterable<Value> arguments,
) extends Instruction {
  /// The argument values in the target's parameter order.
  @override
  final List<Value> inputs = .unmodifiable(arguments);

  /// Creates a call from the already evaluated [arguments].
  ///
  /// Throws [ArgumentError] for a wrong argument count or an incompatible type.
  this : super(target.returnType) {
    checkArguments(target.parameterTypes, inputs);
  }
}

/// Checks the arity and assignability of [arguments] against [types].
void checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length || !type.accepts(arguments[i++].type)) {
      throw ArgumentError('Argument types do not match the parameters.');
    }
  }
  if (i != arguments.length) throw ArgumentError('Unexpected arguments.');
}
