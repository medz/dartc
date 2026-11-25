Future<void> main() async {
  var v = 0;
  final read = () => v;
  for (v in <int>[1, 2, 3]) {}
  print((read(), v)); // expect: (3, 3)
  var w = 0;
  var n = 0;
  while (n++ < 2) {
    for (w in [n, n * 2]) {
      if (w == 4) break;
    }
  }
  print(w); // expect: 4
  var u = 'a';
  final r2 = () => u;
  await for (u in Stream.fromIterable(['x', 'y'])) {
    print(r2());
  }
  // expect: x
  // expect: y
  print((u, r2())); // expect: (y, y)
  late int z;
  final r3 = () => z;
  for (z in [5]) {}
  print(r3()); // expect: 5
  num k = 0;
  void f() {
    for (k in <int>[4, 9]) {}
  }

  f();
  print(k); // expect: 9
  void g(int p) {
    final q = () => p;
    for (p in [8]) {}
    print(q());
  }

  g(1); // expect: 8
  final l = [
    for (v in [10, 11]) read(),
  ];
  print(l); // expect: [10, 11]
  final fs = <int Function()>[];
  int m = 0;
  for (m in [1, 2]) {
    fs.add(() => m);
  }
  print(fs.map((f) => f()).toList()); // expect: [2, 2]
}
