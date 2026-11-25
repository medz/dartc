Iterable<int> count(int n) sync* {
  print('start');
  for (var i = 0; i < n; i++) {
    yield i;
  }
  print('end');
}

Iterable<int> down(int n) sync* {
  while (n > 0) yield n--;
}

Iterable<T> twice<T>(Iterable<T> all) sync* {
  for (final e in all) {
    yield e;
    yield e;
  }
}

Iterable<int> tree(int depth) sync* {
  if (depth == 0) return;
  yield* tree(depth - 1);
  yield depth;
  yield* tree(depth - 1);
}

Iterable<Object?> mixed() sync* {
  yield 1;
  yield* [2, 'a'];
  yield null;
  yield* const {}.keys;
  yield 2.5;
}

class Node {
  final int v;
  final List<Node> kids;
  Node(this.v, [this.kids = const []]);
  Iterable<int> get all sync* {
    yield v;
    for (final k in kids) yield* k.all;
  }

  Iterable<int> operator ~() sync* {
    yield -v;
  }
}

Iterable<int> fib() sync* {
  var (a, b) = (0, 1);
  while (true) {
    yield a;
    (a, b) = (b, a + b);
  }
}

main() {
  print(count(3).toList());
  // expect: start
  // expect: end
  // expect: [0, 1, 2]
  final it = count(2);
  print(it.first);
  // expect: start
  // expect: 0
  print(it.length);
  // expect: start
  // expect: end
  // expect: 2
  final d = down(3);
  print(d.toList()); // expect: [3, 2, 1]
  print(d.toList()); // expect: [3, 2, 1]
  print(twice(['a', 'b']).toList()); // expect: [a, a, b, b]
  print(twice([1]).runtimeType.toString().contains('int')); // expect: true
  print(tree(3).join(',')); // expect: 1,2,1,3,1,2,1
  print(mixed().toList()); // expect: [1, 2, a, null, 2.5]
  print(
    Node(1, [
      Node(2),
      Node(3, [Node(4)]),
    ]).all.toList(),
  ); // expect: [1, 2, 3, 4]
  print((~Node(5)).toList()); // expect: [-5]
  print(fib().skip(5).take(5).toList()); // expect: [5, 8, 13, 21, 34]
  final i = count(1).iterator;
  print(i.moveNext());
  // expect: start
  // expect: true
  print(i.current); // expect: 0
  print(i.moveNext());
  // expect: end
  // expect: false
  print(i.moveNext()); // expect: false
  Iterable<int> local(int k) sync* {
    void add() => k += 10;
    yield k;
    add();
    yield k;
  }

  final l = local(1);
  print(l.toList()); // expect: [1, 11]
  print(l.toList()); // expect: [1, 11]
  var outer = 0;
  final c = () sync* {
    outer++;
    yield outer;
  };
  print(c().toList()); // expect: [1]
  final o = c();
  print(o.toList()); // expect: [2]
  print(o.toList()); // expect: [3]
  print([for (final x in fib().take(4)) x * 2]); // expect: [0, 2, 2, 4]
  for (final (a, b) in fib().indexed.take(3)) print('$a$b');
  // expect: 00
  // expect: 11
  // expect: 21
  Iterable<num> n = count(1);
  print(n is Iterable<int>); // expect: true
  dynamic dy = count;
  print(dy(2).last);
  // expect: start
  // expect: end
  // expect: 1
}
