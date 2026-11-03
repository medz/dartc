import 'signature.dart';

/// An SSA operand. Nonconstant values refer to a single definition by identity.
sealed class Value {
  final ValueType type;
  const Value(this.type);
}

final class Constant extends Value {
  final Object value;
  const Constant.integer(int this.value) : super(ValueType.integer);
  const Constant.boolean(bool this.value) : super(ValueType.boolean);
}

final class BlockParameter extends Value {
  BlockParameter._(super.type) {
    if (type == ValueType.voidType) {
      throw ArgumentError('A block parameter must carry a value.');
    }
  }
}

List<BlockParameter> blockParameters(Iterable<ValueType> types) =>
    List.unmodifiable(types.map(BlockParameter._));

sealed class Instruction extends Value {
  Instruction(super.type);
  Iterable<Value> get inputs;
}

enum IntOperator {
  add(ValueType.integer),
  subtract(ValueType.integer),
  multiply(ValueType.integer),
  lessThan(ValueType.boolean);

  final ValueType result;
  const IntOperator(this.result);
}

final class IntBinary extends Instruction {
  final IntOperator operator;
  final Value left;
  final Value right;

  IntBinary(this.operator, this.left, this.right) : super(operator.result) {
    if (left.type != ValueType.integer || right.type != ValueType.integer) {
      throw ArgumentError('Integer operands required.');
    }
  }

  @override
  Iterable<Value> get inputs => [left, right];
}

/// A direct call in execution order. It may mutate state or unwind to the caller.
final class DirectCall extends Instruction {
  final FunctionTarget target;
  @override
  final List<Value> inputs;

  DirectCall(this.target, Iterable<Value> arguments)
    : inputs = List.unmodifiable(arguments),
      super(target.returnType) {
    checkArguments(target.parameterTypes, inputs);
  }
}

void checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length || arguments[i++].type != type) {
      throw ArgumentError('Argument types do not match the parameters.');
    }
  }
  if (i != arguments.length) throw ArgumentError('Unexpected arguments.');
}
