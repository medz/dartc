import 'block.dart';
import 'signature.dart';
import 'value.dart';

/// Checks control flow, argument and return types, and SSA definition dominance.
void verifyFunction(FunctionTarget target, List<Block> blocks) {
  if (blocks.isEmpty) throw StateError('Function has no entry.');
  final entry = blocks.first;
  checkArguments(target.parameterTypes, entry.parameters);
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
    for (final next in block.successors) {
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
        if (target.returnType != .voidType &&
            value?.type != target.returnType) {
          throw StateError('Return type does not match the function.');
        }
        if (value != null) use(value, count);
      case Branch(:final condition):
        use(condition, count);
      case Jump():
        break;
    }
    for (final edge in block.successors) {
      for (final value in edge.arguments) {
        use(value, count);
      }
    }
  }
}

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
      for (final next in block.successors) {
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
        // A strict dominator has a larger DFS postorder number than its descendants.
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
