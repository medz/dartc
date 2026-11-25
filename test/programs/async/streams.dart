import 'dart:async';

Stream<int> count(int n) async* {
  print('listen');
  try {
    for (var i = 0; i < n; i++) {
      await null;
      yield i;
    }
  } finally {
    print('closed');
  }
}

Stream<T> both<T>(Stream<T> a, Stream<T> b) async* {
  yield* a;
  yield* b;
}

Stream<int> fails() async* {
  yield 1;
  throw 'failed';
}

class S {
  final n = 3;
  Stream<int> get s async* {
    for (var i = 0; i < n; i++) yield i * n;
  }
}

Future<int> find(Stream<int> s, int x) async {
  await for (final v in s) {
    if (v == 0) continue;
    print('see $v');
    if (v == x) return v;
    if (v > 5) break;
  }
  return -1;
}

main() async {
  await for (final v in count(3)) print(v);
  // expect: listen
  // expect: 0
  // expect: 1
  // expect: 2
  // expect: closed
  print(await count(4).toList());
  // expect: listen
  // expect: closed
  // expect: [0, 1, 2, 3]
  print(await find(count(9), 2));
  // expect: listen
  // expect: see 1
  // expect: see 2
  // expect: closed
  // expect: 2
  print(await find(count(20), 99));
  // expect: listen
  // expect: see 1
  // expect: see 2
  // expect: see 3
  // expect: see 4
  // expect: see 5
  // expect: see 6
  // expect: closed
  // expect: -1
  print(await both(count(1), count(2)).join(','));
  // expect: listen
  // expect: closed
  // expect: listen
  // expect: closed
  // expect: 0,0,1
  print(
    await S().s.map((x) => x + 1).where((x) => x.isOdd).toList(),
  ); // expect: [1, 7]
  try {
    await for (final v in fails()) print(v);
  } catch (e) {
    print(e);
  }
  // expect: 1
  // expect: failed
  // expect: h failed
  print(
    await fails().handleError((e) => print('h $e')).toList(),
  ); // expect: [1]
  print(await Stream.fromIterable([1, 2, 3]).fold<int>(0, (a, b) => a + b));
  // expect: 6
  // expect: listen
  // expect: closed
  print(await count(5).take(2).toList()); // expect: [0, 1]
  print(await count(3).first);
  // expect: listen
  // expect: closed
  // expect: 0
  print(
    await Stream.periodic(
      Duration(milliseconds: 12),
      (i) => i,
    ).take(3).toList(),
  ); // expect: [0, 1, 2]
  try {
    await Stream<int>.empty().first;
  } catch (e) {
    print(e);
  }
  // expect: Bad state: No element
  // expect: got a
  // expect: err b
  // expect: got c
  // expect: done
  // expect: 1: 5
  // expect: 2: 5
  // expect: listen
  // expect: 0
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 5
  // expect: 6
  // expect: 7
  // expect: 8
  // expect: 9
  // expect: 10
  // expect: 11
  // expect: 12
  // expect: 13
  // expect: 14
  // expect: 15
  // expect: 16
  // expect: 17
  // expect: 18
  // expect: 19
  // expect: 20
  // expect: 21
  // expect: 22
  // expect: 23
  // expect: 24
  // expect: 25
  // expect: 26
  // expect: 27
  // expect: 28
  // expect: 29
  // expect: 30
  // expect: 31
  // expect: 32
  // expect: 33
  // expect: 34
  // expect: 35
  // expect: 36
  // expect: 37
  // expect: 38
  // expect: 39
  // expect: 40
  // expect: 41
  // expect: 42
  // expect: 43
  // expect: 44
  // expect: 45
  // expect: 46
  // expect: 47
  // expect: 48
  // expect: 49
  // expect: 50
  // expect: 51
  // expect: 52
  // expect: 53
  // expect: 54
  // expect: 55
  // expect: 56
  // expect: 57
  // expect: 58
  // expect: 59
  // expect: 60
  // expect: 61
  // expect: 62
  // expect: 63
  // expect: 64
  // expect: 65
  // expect: 66
  // expect: 67
  // expect: 68
  // expect: 69
  // expect: 70
  // expect: 71
  // expect: 72
  // expect: 73
  // expect: 74
  // expect: 75
  // expect: 76
  // expect: 77
  // expect: 78
  // expect: 79
  // expect: 80
  // expect: 81
  // expect: 82
  // expect: 83
  // expect: 84
  // expect: 85
  // expect: 86
  // expect: 87
  // expect: 88
  // expect: 89
  // expect: 90
  // expect: 91
  // expect: 92
  // expect: 93
  // expect: 94
  // expect: 95
  // expect: 96
  // expect: 97
  // expect: 98
  // expect: 99
  // expect: closed
  final c = StreamController<String>();
  final sub = c.stream.listen(
    (s) => print('got $s'),
    onDone: () => print('done'),
    onError: (e) => print('err $e'),
  );
  c.add('a');
  c.addError('b');
  sub.pause();
  c.add('c');
  await null;
  sub.resume();
  await c.close();
  final b = StreamController<int>.broadcast();
  b.stream.listen((x) => print('1: $x'));
  b.stream.listen((x) => print('2: $x'));
  b.add(5);
  await b.close();
  final st = count(100).listen(print);
  await Future.delayed(Duration(milliseconds: 12));
  st.pause();
  await st.cancel();
  outer:
  await for (final a in count(3)) {
    await for (final (x, y) in Stream.fromIterable([(1, 2), (3, 4)])) {
      if (a == 1) continue outer;
      if (a == 2) break outer;
      print('$a $x $y');
    }
  }
  // expect: listen
  // expect: 0 1 2
  // expect: 0 3 4
  // expect: closed
  final it = StreamIterator(count(2));
  while (await it.moveNext()) print(it.current);
  // expect: listen
  // expect: 0
  // expect: 1
  // expect: closed
  print([await for (final v in count(2)) v * 2]);
  // expect: listen
  // expect: closed
  // expect: [0, 2]
  // expect: listen
  // expect: closed
  print(
    await count(3)
        .transform(
          StreamTransformer<int, String>.fromHandlers(
            handleData: (d, sink) {
              sink.add('<$d>');
            },
          ),
        )
        .toList(),
  ); // expect: [<0>, <1>, <2>]
  Stream<int> local() async* {
    yield* Stream.fromFuture(Future.value(8));
  }

  print(await local().single); // expect: 8
  dynamic dy = count(2);
  await for (final v in dy) print('dyn $v');
  // expect: listen
  // expect: dyn 0
  // expect: dyn 1
  // expect: closed
  print(await count(4).asyncMap((x) async => x * x).toList());
  // expect: listen
  // expect: closed
  // expect: [0, 1, 4, 9]
  // expect: listen
  // expect: closed
  print(await count(2).expand((x) => [x, x]).length); // expect: 4
  final un = await count(3).reduce((a, b) => a + b);
  // expect: listen
  // expect: closed
  print(un); // expect: 3
}
