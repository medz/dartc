import 'signature.dart';

/// An operand in static single assignment (SSA) form.
///
/// A use refers to its defining instruction or block parameter by identity.
/// A [Constant] can be used in any block.
sealed class const Value(
  /// The static Dart type before machine representation selection.
  final ValueType type,
);

/// An integer or boolean literal that requires no instruction to produce it.
final class const Constant._(
  /// The Dart `int` or `bool` represented by this operand.
  final Object value,
  super.type,
) extends Value {
  /// Creates an integer literal with the value [value].
  const new integer(int value) : this._(value, .integer);

  /// Creates a boolean literal with the value [value].
  const new boolean(bool value) : this._(value, .boolean);
}

/// A value supplied on entry to a block by the caller or an incoming jump.
final class BlockParameter._(super.type) extends Value {
  this {
    if (type == .voidType) {
      throw ArgumentError('A block parameter must carry a value.');
    }
  }
}

/// Allocates a distinct SSA parameter for each entry in [types].
List<BlockParameter> blockParameters(Iterable<ValueType> types) =>
    .unmodifiable(types.map(BlockParameter._));

/// An operation executed at its position in a block's instruction list.
sealed class Instruction(super.type) extends Value {
  /// The SSA operands consumed by the operation.
  Iterable<Value> get inputs;
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
  /// Throws [ArgumentError] if their count or types differ from the signature.
  this : super(target.returnType) {
    checkArguments(target.parameterTypes, inputs);
  }
}

/// Checks that [arguments] match [types] in both arity and positional type.
void checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length || arguments[i++].type != type) {
      throw ArgumentError('Argument types do not match the parameters.');
    }
  }
  if (i != arguments.length) throw ArgumentError('Unexpected arguments.');
}
