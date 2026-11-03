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

/// A canonical tear-off of a top-level function, static method or constructor.
final class FunctionConstant(
  /// The referenced declaration, including the source factory for a redirect.
  final FunctionTarget target,
) extends Constant {
  this : super(target.signature) {
    if (target.kind == .closure ||
        target.kind.isVirtual ||
        target.kind == .initializer && target.owner!.isAbstract) {
      throw ArgumentError('Expected a callable without a bound receiver.');
    }
  }
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

/// An operand supplied by the runtime only on an exceptional edge.
final class const UnwindValue._(super.type) extends Value {
  /// The non-null exception that caused control to leave the operation.
  static const exception = UnwindValue._(.object);

  /// The stack trace associated with that throw.
  static const stackTrace = UnwindValue._(.stackTrace);
}

/// Allocates a distinct SSA parameter for each entry in [types].
List<BlockParameter> blockParameters(Iterable<ValueType> types) =>
    .unmodifiable(types.map(BlockParameter._));

/// An operation executed at its position in a block's instruction list.
sealed class Instruction(super.type) extends Value {
  /// The SSA operands consumed by the operation.
  Iterable<Value> get inputs;

  /// Whether evaluation can transfer control to a Dart exception handler.
  bool get mayThrow => switch (this) {
    DirectCall() ||
    InstanceCall() ||
    FunctionCall() ||
    BindMethod() ||
    MakeClosure() ||
    NewCell() ||
    Construct() ||
    TypeCast() ||
    NullCheck() ||
    MakeRecord() => true,
    Equals(:final mayCallUserCode) => mayCallUserCode,
    IntBinary(:final operator) => operator.mayThrow,
    ReadCell() ||
    WriteCell() ||
    TypeTest() ||
    RecordGet() ||
    StoreField() ||
    LoadField() => false,
  };
}

/// Creates a local function value retaining its capture slots by identity.
final class MakeClosure(
  /// The body executed by this closure.
  final FunctionTarget target,
  Iterable<Value> captures,
) extends Instruction {
  /// The captured values or shared cells in entry order.
  @override
  final List<Value> inputs = .unmodifiable(captures);
  this : super(target.signature) {
    if (target.kind != .closure) {
      throw ArgumentError('Expected a lexical function.');
    }
    checkArguments(target.captures, inputs);
  }
}

/// Allocates shared storage for one activation of a captured variable.
final class NewCell(
  CellType type,

  /// The starting value for this activation.
  final Value initial,
) extends Instruction {
  this : super(type) {
    if (!type.content.accepts(initial.type)) {
      throw ArgumentError('Incorrect capture initializer.');
    }
  }
  @override
  Iterable<Value> get inputs => [initial];
}

/// Reads the current value of a captured variable.
final class ReadCell(
  /// The shared storage to read.
  final Value cell,
) extends Instruction {
  this
    : super(switch (cell.type) {
        CellType(:final content) => content,
        _ => throw ArgumentError('Expected capture storage.'),
      });
  @override
  Iterable<Value> get inputs => [cell];
}

/// Replaces the value observed by all closures sharing [cell].
final class WriteCell(
  /// The shared storage to write.
  final Value cell,

  /// The new variable value.
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    final type = cell.type;
    if (type is! CellType || !type.content.accepts(value.type)) {
      throw ArgumentError('Incorrect capture write.');
    }
  }
  @override
  Iterable<Value> get inputs => [cell, value];
}

/// Binds a method to its evaluated receiver, performing virtual selection at extraction.
final class BindMethod(
  /// The method selected statically at this access.
  final FunctionTarget method,

  /// The receiver retained for subsequent calls.
  final Value receiver, {

  /// Whether `super` has already selected the implementation.
  final bool direct = false,
}) extends Instruction {
  this : super(method.signature) {
    if (method.kind != .method ||
        !method.owner!.accepts(receiver.type) ||
        direct && method.isAbstract) {
      throw ArgumentError('Invalid method tear-off.');
    }
  }
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Invokes a function value with the supplied arguments and the destination's defaults.
final class FunctionCall(
  /// The evaluated function value.
  final Value function,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
]) extends Instruction {
  /// Supplied positional arguments.
  final List<Value> positional = .unmodifiable(positional);

  /// Supplied named arguments.
  final Map<String, Value> named = .unmodifiable(named);
  this
    : super(switch (function.type) {
        FunctionType(:final result) => result,
        _ => throw ArgumentError('Expected a non-nullable function signature.'),
      }) {
    _checkCall(function.type as FunctionType, this.positional, this.named);
  }
  @override
  Iterable<Value> get inputs => [function, ...positional, ...named.values];
}

void _checkCall(
  FunctionType signature,
  List<Value> positional,
  Map<String, Value> named,
) {
  final slots = signature.bind<Value?>(positional, named, (_) => null);
  for (final (i, value) in slots.indexed) {
    if (value != null && !signature.parameters[i].accepts(value.type)) {
      throw ArgumentError('Incompatible argument for ${signature.dartName}.');
    }
  }
}

/// Reads storage selected by its declaring class, without invoking a getter.
final class LoadField(
  /// The declared slot to read.
  final InstanceField field,

  /// The object containing the slot.
  final Value receiver,
) extends Instruction {
  this : super(field.type) {
    if (!field.owner.accepts(receiver.type)) {
      throw ArgumentError('Incompatible field receiver.');
    }
  }
  @override
  Iterable<Value> get inputs => [receiver];
}

/// Invokes a member on the runtime class with the arguments supplied by the caller.
///
/// The implementation supplies its own optional defaults and performs its
/// parameter type checks before entering the body.
final class InstanceCall(
  /// The statically resolved member and signature.
  final FunctionTarget member,

  /// The evaluated dispatch receiver.
  final Value receiver,
  Iterable<Value> positional, [
  Map<String, Value> named = const {},
]) extends Instruction {
  /// Explicit positional arguments.
  final List<Value> positional = .unmodifiable(positional);

  /// Explicit named arguments, in their source order.
  final Map<String, Value> named = .unmodifiable(named);
  this : super(member.returnType) {
    if (!member.kind.isVirtual || !member.owner!.accepts(receiver.type)) {
      throw ArgumentError('Incompatible dispatch receiver.');
    }
    _checkCall(member.signature, this.positional, this.named);
  }

  @override
  Iterable<Value> get inputs sync* {
    yield receiver;
    yield* positional;
    yield* named.values;
  }
}

/// Allocates a fresh object, runs [initializer] on it and returns it on success.
///
/// Nullable instance slots without an initializer start as `null`.
final class Construct(
  /// The generative constructor of the allocated class.
  final FunctionTarget initializer,
  Iterable<Value> arguments,
) extends Instruction {
  @override
  final List<Value> inputs = .unmodifiable(arguments);

  this
    : super(
        initializer.owner ?? (throw ArgumentError('Expected a constructor.')),
      ) {
    if (initializer.kind != .initializer || initializer.owner!.isAbstract) {
      throw ArgumentError('Expected a concrete generative constructor.');
    }
    checkArguments(initializer.parameterTypes.skip(1), inputs);
  }
}

/// Stores [value] directly in [field] during instance initialization.
final class StoreField(
  /// The slot selected by its declaring class.
  final InstanceField field,

  /// The object containing the slot.
  final Value receiver,

  /// The value written to the slot.
  final Value value,
) extends Instruction {
  this : super(.voidType) {
    if (!field.owner.accepts(receiver.type) ||
        !field.type.accepts(value.type)) {
      throw ArgumentError('Incompatible instance field write.');
    }
  }

  @override
  Iterable<Value> get inputs => [receiver, value];
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
  this : super(.boolean) {
    if (operand.type is CellType || testedType is CellType) {
      throw ArgumentError('A Dart type test cannot inspect storage.');
    }
  }

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
  this {
    if (operand.type is CellType || type is CellType) {
      throw ArgumentError('A Dart cast cannot expose storage.');
    }
  }

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

  /// IEEE division of the two integers.
  divide(.floating),

  /// Division truncated toward zero.
  truncateDivide(.integer),

  /// Euclidean modulo.
  modulo(.integer),

  /// Bitwise conjunction.
  bitAnd(.integer),

  /// Bitwise disjunction.
  bitOr(.integer),

  /// Bitwise exclusive or.
  bitXor(.integer),

  /// Left shift by a non-negative count.
  shiftLeft(.integer),

  /// Sign-extending right shift.
  shiftRight(.integer),

  /// Zero-extending right shift.
  unsignedShiftRight(.integer),

  /// Whether the left operand is smaller than the right.
  lessThan(.boolean),

  /// Whether the left operand is smaller than or equal to the right.
  lessOrEqual(.boolean),

  /// Whether the left operand is greater than the right.
  greaterThan(.boolean),

  /// Whether the left operand is greater than or equal to the right.
  greaterOrEqual(.boolean);

  /// Whether the operands can trigger a Dart arithmetic or shift error.
  bool get mayThrow => switch (this) {
    truncateDivide ||
    modulo ||
    shiftLeft ||
    shiftRight ||
    unsignedShiftRight => true,
    _ => false,
  };
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
    if (target.kind == .closure) {
      throw ArgumentError('A lexical invocation requires its closure.');
    }
    if (target.redirect != null) {
      throw ArgumentError('Bind arguments to the redirect destination.');
    }
    if (target.isAbstract) {
      throw ArgumentError('Cannot directly invoke an abstract member.');
    }
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
