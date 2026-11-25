Iterable<int> f(int n) sync* {
  try {
    yield 1;
    if (n == 1) throw 'one';
    if (n == 2) return;
    yield 2;
  } on String catch (e) {
    print('caught $e');
    yield 10;
  } finally {
    print('finally $n');
    yield 100;
  }
  yield 3;
}

Iterable<int> g() sync* {
  yield 1;
  throw StateError('bad');
}

Iterable<int> h() sync* {
  try {
    yield* g();
  } catch (e) {
    print('h $e');
    yield 7;
  }
}

Iterable<int> nested() sync* {
  outer:
  for (var i = 0; i < 4; i++) {
    try {
      for (var j = 0; j < 3; j++) {
        try {
          if (i == 1) continue outer;
          if (i == 2 && j == 1) break outer;
          yield i * 10 + j;
        } finally {
          print('in $i$j');
        }
      }
    } finally {
      print('out $i');
      yield -i;
    }
  }
}

Iterable<int> sw(Object o) sync* {
  switch (o) {
    case int n when n > 1:
      yield n;
    case (int a, int b):
      yield a;
      yield b;
    case [var x, ...]:
      yield 9;
    default:
      yield 0;
  }
}

Iterable<String> catches() sync* {
  for (var i = 0; i < 3; i++) {
    try {
      if (i == 1) throw i;
      yield 'ok $i';
    } catch (e, s) {
      yield 'e$e';
      try {
        rethrow;
      } catch (e2) {
        yield 'again $e2';
      }
    }
  }
}

Iterable<int> bad(Iterable<int>? other) sync* {
  yield* other!;
}

main() {
  for (var n = 0; n < 3; n++) print(f(n).toList());
  // expect: finally 0
  // expect: [1, 2, 100, 3]
  // expect: caught one
  // expect: finally 1
  // expect: [1, 10, 100, 3]
  // expect: finally 2
  // expect: [1, 100]
  try {
    print(g().toList());
  } catch (e) {
    print(e);
  }
  // expect: Bad state: bad
  final i = g().iterator;
  print(i.moveNext()); // expect: true
  try {
    i.moveNext();
  } catch (e) {
    print(e);
  }
  // expect: Bad state: bad
  print(i.moveNext()); // expect: false
  print(h().toList());
  // expect: h Bad state: bad
  // expect: [1, 7]
  print(nested().toList());
  // expect: in 00
  // expect: in 01
  // expect: in 02
  // expect: out 0
  // expect: in 10
  // expect: out 1
  // expect: in 20
  // expect: in 21
  // expect: out 2
  // expect: [0, 1, 2, 0, -1, 20, -2]
  print(sw(5).toList()); // expect: [5]
  print(sw((1, 2)).toList()); // expect: [1, 2]
  print(sw([1]).toList()); // expect: [9]
  print(sw('x').toList()); // expect: [0]
  print(catches().toList()); // expect: [ok 0, e1, again 1, ok 2]
  try {
    bad(null).toList();
  } catch (e) {
    print(e);
  }
  // expect: Null check operator used on a null value
  for (final x in f(0)) {
    print(x);
    if (x == 2) break;
  }
  // expect: 1
  // expect: 2
  // expect: finally 0
  late final late1 = f(0).length;
  print(late1); // expect: 4
  double total = 0;
  Iterable<double> ds(bool b) sync* {
    double x = 0.5;
    bool flag = b;
    for (var i = 0; i < 3; i++) {
      x *= 2;
      if (flag) yield x;
      flag = !flag;
    }
  }

  for (final x in ds(true)) total += x;
  print(total); // expect: 5.0
}
