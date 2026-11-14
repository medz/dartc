import 'block.dart';
import 'function.dart';
import 'value.dart';

/// SSA availability in one verified function, including exceptional edges.
final class ValueDominance(final IrFunction function) {
  final _definitions = <Value, (Block, int)>{};
  final _edges = <Jump, List<Block>>{};
  late final Map<Block, Block> _parents;

  this {
    final predecessors = {
      for (final block in function.blocks) block: <Block>[],
    };
    for (final block in function.blocks) {
      for (final parameter in block.parameters) {
        _definitions[parameter] = (block, -1);
      }
      for (final (index, operation) in block.instructions.indexed) {
        _definitions[operation] = (block, index);
      }
      switch (block.end) {
        case Invoke(:final operation):
          _definitions[operation] = (block, block.instructions.length);
        case Await(:final result):
          _definitions[result] = (block, block.instructions.length);
        default:
          break;
      }
      for (final edge in block.successors) {
        (_edges[edge] ??= []).add(block);
        predecessors[edge.target]!.add(block);
      }
    }
    _parents = immediateDominators(function.entry, predecessors);
  }

  /// Whether [value] is available before the source definition [use] executes.
  bool before(Value value, Value use) {
    final position = _definitions[use];
    if (position == null) {
      throw ArgumentError('Use belongs to another function.');
    }
    return _at(value, position.$1, position.$2);
  }

  /// Whether [value] is available when entering [block].
  bool atEntry(Value value, Block block) {
    if (!_parents.containsKey(block)) {
      throw ArgumentError('Block belongs to another function.');
    }
    return _at(value, block, -1);
  }

  /// Whether [value] can be passed on this exact control-flow edge.
  bool onEdge(Value value, Jump edge) {
    final owners = _edges[edge];
    if (owners == null)
      throw ArgumentError('Edge belongs to another function.');
    return owners.every((block) => _onEdge(value, edge, block));
  }

  bool _onEdge(Value value, Jump edge, Block block) {
    final end = block.end;
    if (value is UnwindValue) {
      return switch (end) {
        Invoke(:final onThrow) => edge == onThrow,
        Throw(:final onThrow) ||
        ExhaustivenessFailure(:final onThrow) ||
        Await(:final onThrow) ||
        YieldStream(:final onThrow) => edge == onThrow,
        _ => false,
      };
    }
    if (value is TestedValue) {
      return end is Branch &&
          end.condition == value.test &&
          edge == (value.outcome ? end.ifTrue : end.ifFalse) &&
          _at(value.test, block, block.instructions.length);
    }
    if (end is Invoke && value == end.operation) return edge == end.onReturn;
    if (end is Await && value == end.result) return edge == end.onResume;
    return _at(value, block, block.instructions.length);
  }

  bool _at(Value value, Block block, int index) {
    if (value is Constant) return true;
    final definition = _definitions[value];
    if (definition == null) return false;
    final (owner, position) = definition;
    if (position == owner.instructions.length) return false;
    if (owner == block) return position < 0 || position < index;
    var parent = block;
    while (parent != owner && parent != function.entry) {
      parent = _parents[parent]!;
    }
    return parent == owner;
  }
}

/// Shared by the graph verifier and SSA availability queries.
Map<Block, Block> immediateDominators(
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
