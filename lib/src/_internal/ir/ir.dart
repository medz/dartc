import 'dart:collection';

enum ValueType { boolean, integer, voidType }

/// A resolved top-level declaration. Calls share this identity with its body.
final class FunctionTarget {
  final Uri library;
  final String name;
  final ValueType returnType;
  final List<ValueType> parameterTypes;

  FunctionTarget(
    this.library,
    this.name,
    this.returnType,
    Iterable<ValueType> parameters,
  ) : parameterTypes = List.unmodifiable(parameters) {
    if (parameterTypes.contains(ValueType.voidType)) {
      throw ArgumentError('A parameter must carry a value.');
    }
  }
}

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
  BlockParameter._(super.type);
}

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
    _checkArguments(target.parameterTypes, inputs);
  }
}

void _checkArguments(Iterable<ValueType> types, List<Value> arguments) {
  var i = 0;
  for (final type in types) {
    if (i == arguments.length || arguments[i++].type != type) {
      throw ArgumentError('Argument types do not match the parameters.');
    }
  }
  if (i != arguments.length) throw ArgumentError('Unexpected arguments.');
}

sealed class Terminator {
  const Terminator();
}

final class Return extends Terminator {
  /// A bare return yields null. A function declared void can still return a value.
  final Value? value;
  const Return([this.value]);
}

final class Jump extends Terminator {
  final Block target;
  final List<Value> arguments;
  Jump(this.target, [Iterable<Value> arguments = const []])
    : arguments = List.unmodifiable(arguments) {
    _checkArguments(target.parameters.map((p) => p.type), this.arguments);
  }
}

final class Branch extends Terminator {
  final Value condition;
  final Jump ifTrue;
  final Jump ifFalse;
  Branch(this.condition, this.ifTrue, this.ifFalse) {
    if (condition.type != ValueType.boolean) {
      throw ArgumentError('Boolean condition required.');
    }
  }
}

final class Block {
  final List<BlockParameter> parameters;
  final _instructions = <Instruction>[];
  late final instructions = UnmodifiableListView(_instructions);
  Terminator? _end;
  Terminator get end => _end ?? (throw StateError('Unterminated block.'));

  Block([Iterable<ValueType> types = const []])
    : parameters = List.unmodifiable(types.map(BlockParameter._)) {
    if (parameters.any((p) => p.type == ValueType.voidType)) {
      throw ArgumentError('A block parameter must carry a value.');
    }
  }

  T emit<T extends Instruction>(T instruction) {
    if (_end != null) throw StateError('Block already terminated.');
    _instructions.add(instruction);
    return instruction;
  }

  void finish(Terminator end) {
    if (_end != null) throw StateError('Block already terminated.');
    _end = end;
  }
}

/// A verified SSA graph. The first block receives the function arguments.
final class IrFunction {
  final FunctionTarget target;
  final List<Block> blocks;
  Block get entry => blocks.first;

  IrFunction(this.target, Iterable<Block> blocks)
    : blocks = List.unmodifiable(blocks) {
    if (this.blocks.isEmpty) throw StateError('Function has no entry.');
    _checkArguments(target.parameterTypes, entry.parameters);
    _verify();
  }

  void _verify() {
    final predecessors = {for (final b in blocks) b: <Block>[]};
    if (predecessors.length != blocks.length) {
      throw StateError('Repeated block.');
    }
    final definitions = <Value, (Block, int)>{};
    for (final block in blocks) {
      void define(Value value, int position) {
        if (definitions.containsKey(value)) {
          throw StateError('Repeated SSA definition.');
        }
        definitions[value] = (block, position);
      }

      for (final parameter in block.parameters) {
        define(parameter, -1);
      }
      for (var i = 0; i < block.instructions.length; i++) {
        define(block.instructions[i], i);
      }
      for (final next in _successors(block)) {
        final incoming = predecessors[next.target];
        if (incoming == null || next.target == entry) {
          throw StateError('Invalid control-flow edge.');
        }
        incoming.add(block);
      }
    }
    final idom = _dominators(entry, predecessors);
    for (final block in blocks) {
      void use(Value value, int position) {
        if (value is Constant) return;
        final definition = definitions[value];
        if (definition == null) {
          throw StateError('Value defined outside this function.');
        }
        final (owner, index) = definition;
        if (owner == block) {
          if (index >= position) {
            throw StateError('Value used before its definition.');
          }
        } else {
          var ancestor = block;
          while (ancestor != owner && ancestor != entry) {
            ancestor = idom[ancestor]!;
          }
          if (ancestor != owner) {
            throw StateError('Value does not dominate its use.');
          }
        }
      }

      final count = block.instructions.length;
      for (var i = 0; i < count; i++) {
        for (final input in block.instructions[i].inputs) {
          use(input, i);
        }
      }
      switch (block.end) {
        case Return(:final value):
          if (target.returnType != ValueType.voidType &&
              value?.type != target.returnType) {
            throw StateError('Return type does not match the function.');
          }
          if (value != null) use(value, count);
        case Branch(:final condition):
          use(condition, count);
        case Jump():
          break;
      }
      for (final edge in _successors(block)) {
        for (final value in edge.arguments) {
          use(value, count);
        }
      }
    }
  }
}

Iterable<Jump> _successors(Block block) => switch (block.end) {
  Return() => const [],
  final Jump jump => [jump],
  Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
};

Map<Block, Block> _dominators(
  Block entry,
  Map<Block, List<Block>> predecessors,
) {
  final visited = <Block>{};
  final order = <Block, int>{};
  final stack = [(entry, false)];
  while (stack.isNotEmpty) {
    final (block, leaving) = stack.removeLast();
    if (leaving) {
      order[block] = order.length;
    } else if (visited.add(block)) {
      stack.add((block, true));
      for (final next in _successors(block)) {
        stack.add((next.target, false));
      }
    }
  }
  if (order.length != predecessors.length) {
    throw StateError('Unreachable block.');
  }
  final reversePostorder = order.keys.toList().reversed.skip(1);
  final idom = {entry: entry};
  bool changed;
  do {
    changed = false;
    for (final block in reversePostorder) {
      Block? parent;
      for (var incoming in predecessors[block]!) {
        if (!idom.containsKey(incoming)) continue;
        parent ??= incoming;
        while (parent != incoming) {
          if (order[parent]! < order[incoming]!) {
            parent = idom[parent]!;
          } else {
            incoming = idom[incoming]!;
          }
        }
      }
      if (parent != idom[block]) {
        idom[block] = parent!;
        changed = true;
      }
    }
  } while (changed);
  return idom;
}
