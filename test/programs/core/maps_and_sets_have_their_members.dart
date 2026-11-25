class K {
  final int n;
  const K(this.n);
  @override
  bool operator ==(Object o) => o is K && o.n == n;
  @override
  int get hashCode => n % 2;
  @override
  String toString() => 'K$n';
}

void main() {
  final m = {'a': 1, 'b': 2};
  m['c'] = 3;
  print(
    '$m ${m['b']} ${m['z']} ${m.length} ${m.keys} ${m.values.toList()} ${m.containsKey('c')} ${m.containsValue(9)}',
  ); // expect: {a: 1, b: 2, c: 3} 2 null 3 (a, b, c) [1, 2, 3] true false
  print(m.remove('a')); // expect: 1
  print(m.remove('q')); // expect: null
  m.forEach((k, v) => print('$k$v'));
  // expect: b2
  // expect: c3
  for (final e in m.entries) {
    print('${e.key}=${e.value}');
  }
  // expect: b=2
  // expect: c=3
  print(m.putIfAbsent('x', () => 9)); // expect: 9
  print(m.update('x', (v) => v + 1)); // expect: 10
  m.addAll({'p': 1});
  print(m.map((k, v) => MapEntry(v, k))); // expect: {2: b, 3: c, 10: x, 1: p}
  m.removeWhere((k, v) => v > 2);
  print(m); // expect: {b: 2, p: 1}
  m.clear();
  print(m.isEmpty); // expect: true
  final big = <int, int>{};
  for (var i = 0; i < 1000; i++) {
    big[i * 7] = i;
  }
  for (var i = 0; i < 1000; i += 3) {
    big.remove(i * 7);
  }
  var sum = 0;
  big.forEach((k, v) => sum += k ^ v);
  print(
    '$sum ${big.length} ${big[14]} ${big[21]}',
  ); // expect: 2294346 666 2 null
  final k = {K(1): 'one', K(3): 'three'};
  k[K(1)] = 'uno';
  print(k); // expect: {K1: uno, K3: three}
  print(k[K(3)]); // expect: three
  final st = {1, 2, 2, 3};
  print(
    '$st ${st.contains(2)} ${st.add(2)} ${st.add(9)} ${st.union({100})} ${st.intersection({1, 9})} ${st.difference({1})} ${st.remove(1)} ${st.length} ${st.lookup(3)} ${st.toList()}',
  ); // expect: {2, 3, 9} true false true {1, 2, 3, 9, 100} {1, 9} {2, 3, 9} true 3 3 [2, 3, 9]
  print({K(1), K(1), K(2)}); // expect: {K1, K2}
  print(
    const {
      'a': 1,
      'b': [1],
    }['b'],
  ); // expect: [1]
  print(const {1, 2}.contains(2)); // expect: true
  print(const {K2.a: 1}.length); // expect: 1
  final n = <String?, int?>{null: null};
  print(n.containsKey(null)); // expect: true
  print(Map.of({1: 2})); // expect: {1: 2}
  print(Map.fromIterable([1, 2], value: (x) => x * 2)); // expect: {1: 2, 2: 4}
  print(Map.fromEntries([MapEntry(1, 2)])); // expect: {1: 2}
  print(Set.of([1, 1])); // expect: {1}
  print(
    <String, List<int>>{}..putIfAbsent('k', () => []).add(1),
  ); // expect: {k: [1]}
  final d = <dynamic, dynamic>{1: 'i', 1.5: 'd', 'a': null, true: 2};
  print('$d ${d[1.0]} ${d[1]}'); // expect: {1: i, 1.5: d, a: null, true: 2} i i
  try {
    (const {1: 2} as Map)[1] = 3;
  } catch (e) {
    print(e);
  }
  // expect: Unsupported operation: Cannot modify unmodifiable map
  try {
    for (final x in st) {
      st.remove(x);
    }
  } catch (e) {
    print('concurrent');
  }
  // expect: concurrent
}

class K2 {
  static const a = 5;
}
