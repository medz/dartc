import 'dart:collection';

final class E extends LinkedListEntry<E> {
  final int n;
  E(this.n);
  @override
  String toString() => 'E$n';
}

void main() {
  final q = Queue<int>()
    ..add(1)
    ..addFirst(0)
    ..addAll([5, 6]);
  print(q); // expect: {0, 1, 5, 6}
  print(q.removeFirst()); // expect: 0
  print(q.removeLast()); // expect: 6
  final s = SplayTreeMap<String, int>()
    ..['b'] = 1
    ..['a'] = 2;
  print(s); // expect: {a: 2, b: 1}
  print(s.firstKey()); // expect: a
  print(SplayTreeSet.of([3, 1, 2])); // expect: {1, 2, 3}
  final h = HashMap<String, int>()
    ..['x'] = 1
    ..['yy'] = 2
    ..['zzz'] = 3;
  print(h); // expect: {yy: 2, x: 1, zzz: 3}
  print(HashSet.of([5, 3, 900, 17])); // expect: {17, 3, 900, 5}
  print(LinkedHashMap.of({1: 2})); // expect: {1: 2}
  final l = LinkedList<E>()
    ..add(E(1))
    ..add(E(2));
  print(l); // expect: (E1, E2)
  l.first.unlink();
  print(l.length); // expect: 1
  print(UnmodifiableListView([1, 2])); // expect: [1, 2]
  print(ListQueue.of([1, 2, 3])); // expect: {1, 2, 3}
  print(HashMap.identity()..[1] = 2); // expect: {1: 2}
  print(MapView({1: 2})); // expect: {1: 2}
  print(UnmodifiableMapView({1: 2})); // expect: {1: 2}
  for (final k in h.keys) {
    print(k);
  }
  // expect: yy
  // expect: x
  // expect: zzz
  print(LinkedHashSet<int>.identity()..add(1)); // expect: {1}
  final m = MapBase.mapToString({1: 2});
  print(m); // expect: {1: 2}
  print(IterableBase.iterableToShortString([1, 2], '(', ')')); // expect: (1, 2)
  final w = HashMap<int, int>(
    equals: (a, b) => a % 10 == b % 10,
    hashCode: (a) => a % 10,
  );
  w[1] = 1;
  w[11] = 2;
  print(w); // expect: {1: 2}
}
