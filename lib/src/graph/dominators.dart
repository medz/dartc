/// The blocks reachable from [entry], each before its successors except along
/// edges that go back to a loop.
List<B> reversePostorder<B>(B entry, Iterable<B> Function(B block) successors) {
  final order = <B>[], visited = {entry};
  final stack = [(entry, successors(entry).iterator)];
  while (stack.isNotEmpty) {
    final (block, next) = stack.last;
    if (!next.moveNext()) {
      order.add(block);
      stack.removeLast();
    } else if (visited.add(next.current)) {
      stack.add((next.current, successors(next.current).iterator));
    }
  }
  return order.reversed.toList();
}

/// Which blocks every path to a block passes through.
final class Dominators<B extends Object>(
  final B entry,
  Iterable<B> Function(B block) successors,
) {
  /// The reachable blocks in reverse postorder.
  final List<B> order = reversePostorder(entry, successors);
  final _parent = <B, B>{};

  this {
    final rank = {for (final (i, block) in order.indexed) block: i};
    final predecessors = <B, List<B>>{};
    for (final block in order) {
      for (final next in successors(block)) {
        (predecessors[next] ??= []).add(block);
      }
    }
    B meet(B a, B b) {
      while (a != b) {
        if (rank[a]! > rank[b]!) {
          a = _parent[a]!;
        } else {
          b = _parent[b]!;
        }
      }
      return a;
    }

    _parent[entry] = entry;
    bool changed;
    do {
      changed = false;
      for (final block in order.skip(1)) {
        final known = predecessors[block]!.where(_parent.containsKey);
        final found = known.reduce(meet);
        if (_parent[block] == found) continue;
        _parent[block] = found;
        changed = true;
      }
    } while (changed);
  }

  /// Whether every path from the entry to [below] passes through [above].
  bool dominates(B above, B below) {
    var block = below;
    while (block != above) {
      if (block == entry) return false;
      block = _parent[block]!;
    }
    return true;
  }
}
