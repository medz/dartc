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

/// A compile-time value that can be used in any block.
sealed class const Constant(super.type) extends Value {
  /// Creates an integer literal with the value [value].
  const factory integer(int value) = ScalarConstant._integer;

  /// Creates a boolean literal with the value [value].
  const factory boolean(bool value) = ScalarConstant._boolean;

  /// Creates a double literal, preserving the sign of zero.
  const factory floating(double value) = ScalarConstant._floating;

  /// Creates a string literal from its decoded [value].
  const factory string(String value) = ScalarConstant._string;

  /// Creates the Dart `null` value.
  const factory nullValue() = ScalarConstant._nullValue;
}

/// A scalar literal with its Dart value and static type.
final class const ScalarConstant._(
  /// The Dart scalar represented by this operand.
  final Object? value,
  super.type,
) extends Constant {
  const new _integer(int value) : this._(value, .integer);
  const new _boolean(bool value) : this._(value, .boolean);
  const new _floating(double value) : this._(value, .floating);
  const new _string(String value) : this._(value, .string);
  const new _nullValue() : this._(null, .nullType);
}

/// A constant record with a constant operand for each slot in its type.
final class RecordConstant(RecordType type, Iterable<Constant> fields)
    extends Constant {
  /// The constant fields in slot order.
  final List<Constant> fields = .unmodifiable(fields);

  this : super(type) {
    checkArguments(type.fields, this.fields);
  }
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

/// Constructs a record from evaluated fields in slot order.
///
/// Runtime type checks use the actual field values. The static [type] may be wider.
final class MakeRecord(RecordType type, Iterable<Value> fields)
    extends Instruction {
  @override
  final List<Value> inputs = .unmodifiable(fields);
  this : super(type) {
    checkArguments(type.fields, inputs);
  }
}

/// Reads an immutable field from a statically known record shape.
final class RecordGet(
  /// The record that supplies the field.
  final Value record,

  /// The index in the record type's field list.
  final int slot,
) extends Instruction {
  this
    : super(switch (record.type) {
        RecordType(:final fields) => fields[slot],
        _ => throw ArgumentError('Expected a record with a known shape.'),
      });

  @override
  Iterable<Value> get inputs => [record];
}

/// A Dart `is` or `is!` test on an already evaluated operand.
final class TypeTest(
  /// The already evaluated operand.
  final Value operand,

  /// The runtime type to match.
  final ValueType testedType, {

  /// Whether to invert the result of the match.
  final bool negated = false,
}) extends Instruction {
  this : super(.boolean);

  /// The value known on the edge with [outcome], or `null` if its type is unchanged.
  Value? refinement(bool outcome) {
    final source = operand.type;
    final ValueType narrowed;
    if (outcome != negated) {
      if (testedType == .nullType) return const Constant.nullValue();
      if (testedType.accepts(source)) return null;
      if (testedType.accepts(source.nonNullable)) {
        narrowed = source.nonNullable;
      } else {
        narrowed = source.accepts(.nullType)
            ? testedType
            : testedType.nonNullable;
      }
    } else if (testedType.accepts(.nullType)) {
      narrowed = source.nonNullable;
    } else if (testedType.accepts(source.nonNullable)) {
      return const Constant.nullValue();
    } else {
      return null;
    }
    return narrowed == source ? null : TestedValue._(this, outcome, narrowed);
  }

  @override
  Iterable<Value> get inputs => [operand];
}

/// A narrower view of an operand on one outgoing edge of [test].
///
/// Only a jump on the side selected by [outcome] may use this value as an
/// argument. Its destination reads an ordinary block parameter.
final class TestedValue._(
  /// The test that establishes this value's type.
  final TypeTest test,

  /// The boolean result required for this refinement.
  final bool outcome,
  super.type,
) extends Value;

/// A Dart `as` cast that throws a type error if [operand] does not match [type].
final class TypeCast(
  /// The value returned unchanged on success.
  final Value operand,
  super.type,
) extends Instruction {
  @override
  Iterable<Value> get inputs => [operand];
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

  /// Whether the left operand is smaller than or equal to the right.
  lessOrEqual(.boolean),

  /// Whether the left operand is greater than the right.
  greaterThan(.boolean),

  /// Whether the left operand is greater than or equal to the right.
  greaterOrEqual(.boolean),
}

/// Dart equality, including the null rule and dispatch on the left operand.
///
/// Comparing records can invoke user-defined equality on their fields.
final class Equals(
  /// The receiver that determines the equality implementation.
  final Value left,

  /// The value compared to [left].
  final Value right, {

  /// Whether to invert the result for `!=`.
  final bool negated = false,
}) extends Instruction {
  this : super(.boolean);

  /// Whether the comparison may call a user-defined equality operator.
  bool get mayCallUserCode => !left.type.hasScalarEquality;
  @override
  Iterable<Value> get inputs => [left, right];
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
