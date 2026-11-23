import 'dart:math';

import 'package:dartc/graph.dart';
import 'package:test/test.dart';

void main() {
  test('order visits each reachable block once, entry first', () {
    final graph = {
      0: [1, 2],
      1: [3],
      2: [3],
      3: [1],
      9: [0],
    };
    final order = reversePostorder(0, (block) => graph[block]!);
    expect(order.first, 0);
    expect(order.toSet(), {0, 1, 2, 3});
    expect(order, hasLength(4));
    expect(order.indexOf(2), lessThan(order.indexOf(3)));
  });

  test('long chains do not overflow the stack', () {
    final order = reversePostorder(0, (n) => [if (n < 200000) n + 1]);
    expect(order, hasLength(200001));
  });

  test('agrees with the definition on random graphs', () {
    final random = Random(7);
    for (var round = 0; round < 300; round++) {
      final size = 1 + random.nextInt(9);
      final graph = [
        for (var i = 0; i < size; i++)
          [for (var j = random.nextInt(3); j > 0; j--) random.nextInt(size)],
      ];
      Set<int> reachable({int? without}) {
        final seen = <int>{}, pending = [0];
        while (pending.isNotEmpty) {
          final block = pending.removeLast();
          if (block != without && seen.add(block)) {
            pending.addAll(graph[block]);
          }
        }
        return seen;
      }

      final dominators = Dominators(0, (block) => graph[block]);
      expect(dominators.order.toSet(), reachable());
      for (final above in reachable()) {
        final around = reachable(without: above);
        for (final below in reachable()) {
          expect(
            dominators.dominates(above, below),
            !around.contains(below),
            reason: '$graph: $above over $below',
          );
        }
      }
    }
  });
}
