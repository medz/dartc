// Components are returned after all components they depend on.
List<List<int>> stronglyConnectedComponents(List<List<int>> edges) {
  final indices = List<int>.filled(edges.length, -1);
  final low = List<int>.filled(edges.length, -1);
  final active = List<bool>.filled(edges.length, false);
  final stack = <int>[];
  final groups = <List<int>>[];
  var next = 0;

  void visit(int vertex) {
    indices[vertex] = next;
    low[vertex] = next;
    next++;
    stack.add(vertex);
    active[vertex] = true;
    for (final target in edges[vertex]) {
      if (indices[target] < 0) {
        visit(target);
        if (low[target] < low[vertex]) low[vertex] = low[target];
      } else if (active[target] && indices[target] < low[vertex]) {
        low[vertex] = indices[target];
      }
    }
    if (low[vertex] == indices[vertex]) {
      final group = <int>[];
      var item = -1;
      while (item != vertex) {
        item = stack.removeLast();
        active[item] = false;
        group.add(item);
      }
      groups.add(group);
    }
  }

  for (var i = 0; i < edges.length; i++) {
    if (indices[i] < 0) visit(i);
  }
  return groups;
}
