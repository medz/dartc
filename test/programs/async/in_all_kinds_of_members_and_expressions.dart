import 'dart:async';

Future<T> w<T>(T x) async {
  await null;
  return x;
}

class Box<T> {
  T v;
  Box(this.v);
  Future<List<T>> list() async => [v, await w(v)];
  Iterable<T> rep(int n) sync* {
    for (var i = 0; i < n; i++) yield v;
  }

  Stream<(int, T)> st(int n) async* {
    for (var i = 0; i < n; i++) {
      yield (i, await w(v));
    }
  }

  Future<R> map<R>(FutureOr<R> Function(T) f) async {
    final r = await f(v);
    print('$T $R');
    return r;
  }

  late final Future<T> lazy = (() async => await w(v))();
  Type get t => T;
  Future<Type> tt() async {
    await null;
    return T;
  }
}

mixin Mx<T> {
  T get mv;
  Future<String> sh() async {
    await null;
    return 'mx $mv ${T}';
  }

  Iterable<T> it() sync* {
    yield mv;
    yield* [mv];
  }
}

class Cx extends Box<String> with Mx<int> {
  Cx(super.v);
  int get mv => v.length;
  @override
  Future<List<String>> list() async {
    final l = await super.list();
    return [...l, 'cx'];
  }

  Future<int> cl() async {
    int f() => mv + 1;
    await null;
    int g() => f() + v.length;
    return g();
  }
}

extension Ex<T> on List<T> {
  Future<T> pick(int i) async {
    await null;
    return this[i];
  }

  Iterable<(int, T)> num_() sync* {
    var i = 0;
    for (final e in this) yield (i++, e);
  }

  Stream<T> get str async* {
    yield* Stream.fromIterable(this);
  }
}

extension type Et(int n) {
  Future<int> dbl() async => n * await w(2);
  Iterable<int> up() sync* {
    for (var i = 0; i < n; i++) yield i;
  }

  static Future<Et> mk(int n) async => Et(await w(n));
}

enum En {
  a,
  b;

  Future<En> next() async {
    await null;
    return values[(index + 1) % 2];
  }
}

Future<int> fin(int k) async {
  try {
    try {
      if (k == 0) return await w(10);
      if (k == 1) throw 'e';
    } finally {
      await w(null);
      print('f1 $k');
      if (k == 2) return 22;
    }
  } on String {
    return 33;
  } finally {
    print('f2 $k');
  }
  return 44;
}

Future<void> lab() async {
  outer:
  for (var i = 0; i < await w(3); i += await w(1)) {
    try {
      for (var j = 0; ; j++) {
        try {
          if (j == 1) continue outer;
          if (i == 2) break outer;
          print('$i $j');
        } finally {
          await null;
          print('in');
        }
      }
    } finally {
      print('out ${await w(i)}');
    }
  }
}

Future<String> sw(Object o) async => switch (o) {
  int n when await w(n > 2) => 'big $n',
  int n => 'small ${await w(n)}',
  [final a, final b] => '${await w(a)}-${await w(b)}',
  (x: final x) => await w('$x'),
  _ => throw ArgumentError('no $o'),
};
Future<int> fib(int n) async => n < 2 ? n : await fib(n - 1) + await fib(n - 2);
Iterable<String> perms(String s) sync* {
  if (s.length <= 1) {
    yield s;
    return;
  }
  for (var i = 0; i < s.length; i++) {
    for (final p in perms(s.replaceRange(i, i + 1, ''))) yield s[i] + p;
  }
}

Stream<int> merge(Stream<int> a, Stream<int> b) {
  final c = StreamController<int>();
  var open = 2;
  void done() {
    if (--open == 0) c.close();
  }

  a.listen(c.add, onDone: done, onError: c.addError);
  b.listen(c.add, onDone: done);
  return c.stream;
}

Future<void> args(int a, [int b = 2, int? c]) async {
  a += await w(1);
  b *= a;
  c ??= await w(b);
  void inc() {
    a++;
    b++;
  }

  inc();
  await null;
  print('$a $b $c');
}

Future<void> named({required int x, String y = 'd'}) async {
  await null;
  print('$x $y');
}

int top = 0;
Future<int> get tg async => ++top;
set ts(int v) {
  () async {
    await null;
    top = v;
  }();
}

Object? thrown() async* {}
main() async {
  final b = Box(3);
  print(await b.list()); // expect: [3, 3]
  print(b.rep(2).toList()); // expect: [3, 3]
  print(await b.st(2).toList()); // expect: [(0, 3), (1, 3)]
  print(await b.map((n) => '$n!'));
  // expect: int Object?
  // expect: 3!
  print(await b.map((n) async => n / 2));
  // expect: int Object?
  // expect: 1.5
  print(await b.lazy); // expect: 3
  print(await b.lazy); // expect: 3
  print(await Box<num>(1).tt()); // expect: num
  final c = Cx('abc');
  print(await c.list()); // expect: [abc, abc, cx]
  print(await c.sh()); // expect: mx 3 int
  print(c.it().toList()); // expect: [3, 3]
  print(await c.cl()); // expect: 7
  print(await c.lazy); // expect: abc
  print(await [1, 2, 3].pick(1)); // expect: 2
  print(['a', 'b'].num_().toList()); // expect: [(0, a), (1, b)]
  print(await ['q'].str.toList()); // expect: [q]
  print(await Et(4).dbl()); // expect: 8
  print(Et(3).up().toList()); // expect: [0, 1, 2]
  print((await Et.mk(5)).n); // expect: 5
  print(await En.b.next()); // expect: En.a
  for (var k = 0; k < 4; k++) print(await fin(k));
  // expect: f1 0
  // expect: f2 0
  // expect: 10
  // expect: f1 1
  // expect: f2 1
  // expect: 33
  // expect: f1 2
  // expect: f2 2
  // expect: 22
  // expect: f1 3
  // expect: f2 3
  // expect: 44
  await lab();
  // expect: 0 0
  // expect: in
  // expect: in
  // expect: out 0
  // expect: 1 0
  // expect: in
  // expect: in
  // expect: out 1
  // expect: in
  // expect: out 2
  for (final o in <Object>[
    1,
    5,
    [1, 2],
    (x: 3),
  ])
    print(await sw(o));
  // expect: small 1
  // expect: big 5
  // expect: 1-2
  // expect: 3
  try {
    await sw('z');
  } catch (e) {
    print(e);
  }
  // expect: Invalid argument(s): no z
  print(await fib(10)); // expect: 55
  print(perms('abcd').length); // expect: 24
  print(perms('abc').toList()); // expect: [abc, acb, bac, bca, cab, cba]
  print(
    (await merge(
      Stream.fromIterable([1, 2]),
      Stream.fromIterable([10, 20]),
    ).toList())..sort(),
  ); // expect: [1, 2, 10, 20]
  await args(1); // expect: 3 5 4
  await args(1, 5, 9); // expect: 3 11 9
  await named(x: await w(1)); // expect: 1 d
  await named(y: 'z', x: 2); // expect: 2 z
  print(await tg + await tg); // expect: 3
  ts = 50;
  await null;
  await null;
  print(top); // expect: 50
  final l = <int>[]
    ..add(await w(1))
    ..addAll([
      await w(2),
      ...await w([3, 4]),
    ]);
  print(l); // expect: [1, 2, 3, 4]
  final m = {
    await w('k'): await w(1),
    for (final e in await w([1, 2])) e: await w(e * e),
    if (await w(true)) 'if': 1,
  };
  print(m); // expect: {k: 1, 1: 1, 2: 4, if: 1}
  String? ns = top > 0 ? null : 'x';
  print(ns?.substring(await w(0)) ?? await w('nul')); // expect: nul
  print(
    'a${await w('b')}c${[for (var i = 0; i < 2; i++) await w(i)]}',
  ); // expect: abc[0, 1]
  var x = await w(5);
  x += await w(x) * 2;
  x -= x - await w(1);
  print(x); // expect: 1
  final fs = [
    for (var i = 0; i < 3; i++)
      () async {
        await null;
        return i * i;
      },
  ];
  print(await Future.wait(fs.map((f) => f()))); // expect: [0, 1, 4]
  print(
    await (() async {
      try {
        return await Future<int>.error('E');
      } on String catch (e) {
        return e.length;
      }
    })(),
  ); // expect: 1
  print(await w(1) < await w(2) && (await w(3)).isOdd); // expect: true
  (await w(b))
    ..v = 7
    ..v += await w(1);
  print(b.v); // expect: 8
  print(
    await Future.wait([
      for (var i = 0; i < 3; i++)
        Future.microtask(() async {
          await null;
          return i;
        }),
    ]),
  ); // expect: [0, 1, 2]
  await for (final (i, s) in Stream.fromIterable([
    'p',
    'q',
  ]).map((s) => (s.length, s)))
    print('$i$s');
  // expect: 1p
  // expect: 1q
  // expect: 1
  // expect: 2
  await Future.forEach(<int>[1, 2], (n) async => print(await w(n)));
  bool flag = false;
  await Future.any([
    w(1).then((_) => flag = true),
    Future.delayed(Duration(milliseconds: 3)),
  ]);
  print(flag); // expect: true
  print((thrown() as Stream).runtimeType.toString().length > 3); // expect: true
  late int lz;
  Future<void> setLz() async {
    lz = await w(9);
  }

  await setLz();
  print(lz); // expect: 9
  print(
    await Stream.fromIterable([3, 1, 2]).asyncExpand((n) async* {
      for (var i = 0; i < n; i++) yield i;
    }).toList(),
  ); // expect: [0, 1, 2, 0, 0, 1]
  int? mb = await w<int?>(null);
  mb ??= await w(4);
  print(mb); // expect: 4
  double dd = await w(1.5);
  dd++;
  bool bb = await w(false);
  bb |= true;
  print('$dd $bb'); // expect: 2.5 true
  final rec = (await w(1), n: await w('r'));
  print(rec); // expect: (1, n: r)
  if (await w((1, 2)) case (var p, var q) when await w(p < q))
    print(p + q); // expect: 3
  do {
    x++;
  } while (await w(x < 4));
  print(x); // expect: 4
  assert(await w(false));
  print(await Function.apply(w, [6])); // expect: 6
}
