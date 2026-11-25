(int, String) pair(int n) => (n, 'n$n');
({int x, double y}) named() => (y: 2.5, x: 1);
(int, {String name, bool ok}) both = (4, ok: true, name: 'b');
(T, T) swap<T>((T, T) p) => (p.$2, p.$1);
int trace(int n) {
  print('t$n');
  return n;
}

const constant = (1, 'a', z: [2]);
void main() {
  final p = pair(3);
  print(p.$1); // expect: 3
  print(p.$2); // expect: n3
  print(p); // expect: (3, n3)
  print(named()); // expect: (x: 1, y: 2.5)
  print(named().x); // expect: 1
  print(both.name); // expect: b
  print(both); // expect: (4, name: b, ok: true)
  print(swap((1, 2))); // expect: (2, 1)
  print(swap(('a', 'b')).$1); // expect: b
  print(p == (3, 'n3')); // expect: true
  print(p == pair(4)); // expect: false
  print(p.hashCode == (3, 'n3').hashCode); // expect: true
  print((a: 1, b: 2) == (b: 2, a: 1)); // expect: true
  print((1, 2) == (a: 1, b: 2)); // expect: false
  Object o = (1, 2);
  print(o == (1, 2, 3)); // expect: false
  print((trace(1), b: trace(2), a: trace(3)));
  // expect: t1
  // expect: t2
  // expect: t3
  // expect: (1, a: 3, b: 2)
  print((1,)); // expect: (1)
  print(()); // expect: ()
  print((null, (2, 3))); // expect: (null, (2, 3))
  print(constant); // expect: (1, a, z: [2])
  print(constant.z.first); // expect: 2
  print(constant == (1, 'a', z: const [2])); // expect: true
  final map = {(1, 2): 'x', (a: 1): 'y'};
  print(map[(1, 2)]); // expect: x
  print(map[(a: 1)]); // expect: y
  (num, Object?) wide = (1, null);
  print(wide.$1); // expect: 1
  print(wide.runtimeType); // expect: (int, Null)
  var r = (1, 2.5);
  r = (2, 3.5);
  print(r.$1 + r.$2); // expect: 5.5
  final list = [(1, 'a'), (2, 'b')];
  print(list); // expect: [(1, a), (2, b)]
  print(list.runtimeType); // expect: List<(int, String)>
  for (final e in list) print(e.$1 * 2);
  // expect: 2
  // expect: 4
  print(['a', 'b'].indexed.toList()); // expect: [(0, a), (1, b)]
}
