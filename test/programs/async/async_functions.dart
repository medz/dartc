import 'dart:async';

Future<int> one() async => 1;
Future<int> add(Future<int> a, int b) async {
  final x = await a;
  print('add $x $b');
  return x + b;
}

Future<void> nothing() async {
  print('nothing');
}

void fire(String s) async {
  print('fire $s');
  await null;
  print('fired $s');
}

Future<T> same<T>(T x) async {
  await 0;
  return x;
}

Future<int> direct() async {
  print('direct');
  return one();
}

Future<double> half(int n) async => n / 2;

class A {
  int n = 0;
  Future<int> inc([int by = 1]) async {
    n += by;
    await Future.value();
    return n;
  }

  Future<int> get v async => n;
  Future<A> operator +(int k) async {
    await inc(k);
    return this;
  }

  static Future<String> name() async => 'A';
}

class B extends A {
  @override
  Future<int> inc([int by = 1]) async {
    print('B.inc');
    return await super.inc(by * 2);
  }
}

mixin M {
  Future<int> m(int k) async {
    await null;
    return k;
  }
}

class C with M {}

main() async {
  print('main'); // expect: main
  fire('a');
  // expect: fire a
  // expect: fired a
  print(await one()); // expect: 1
  print(await add(one(), 2));
  // expect: add 1 2
  // expect: 3
  await nothing(); // expect: nothing
  print(await same('s')); // expect: s
  print(await direct());
  // expect: direct
  // expect: 1
  print(await half(3)); // expect: 1.5
  final a = B();
  print(await a.inc());
  // expect: B.inc
  // expect: 2
  print(await a.inc(5));
  // expect: B.inc
  // expect: 12
  print(await a.v); // expect: 12
  print((await (a + 1)).n);
  // expect: B.inc
  // expect: 14
  print(await A.name()); // expect: A
  print(await C().m(6)); // expect: 6
  final f = one();
  print(f is Future<int>); // expect: true
  print(await f + await f); // expect: 2
  print([
    await one(),
    2,
    for (var i = 0; i < 3; i++) await same(i),
  ]); // expect: [1, 2, 0, 1, 2]
  print('${await one()} ${await same(true)}'); // expect: 1 true
  var sum = 0;
  for (var i = 0; i < 5; i++) {
    sum += await add(Future.value(i), i);
  }
  // expect: add 0 0
  // expect: add 1 1
  // expect: add 2 2
  // expect: add 3 3
  // expect: add 4 4
  print(sum); // expect: 20
  while (await same(sum > 0)) {
    sum -= 25;
    if (sum < 0) break;
  }
  print(sum); // expect: -5
  final g = () async {
    print('g');
    await null;
    return 'g done';
  };
  print(await g());
  // expect: g
  // expect: g done
  Future<int> local(int n) async {
    if (n <= 1) return 1;
    return n * await local(n - 1);
  }

  print(await local(5)); // expect: 120
  print(await (await same(one))()); // expect: 1
  dynamic d = one();
  print(await d); // expect: 1
  Object o = one();
  print(await o); // expect: 1
  int i = 3;
  print(await i); // expect: 3
  FutureOr<int> fo = 4;
  print(await fo); // expect: 4
  fo = one();
  print(await fo); // expect: 1
  int? nul = sum > 9 ? 1 : null;
  print(await nul); // expect: null
  print(await (sum > 0 ? one() : same(2))); // expect: 2
  print(await Future.wait([one(), same(2), half(4).then((x) => x.toInt())]));
  // expect: [1, 2, 2]
  // expect: complete
  print(await one().then((x) => x * 10).whenComplete(() => print('complete')));
  // expect: 10
  // expect: d2
  // expect: d1
  // expect: d0
  final fs = <Future<int>>[];
  for (var k = 0; k < 3; k++)
    fs.add(
      Future.delayed(Duration(milliseconds: 90 - 40 * k), () {
        print('d$k');
        return k;
      }),
    );
  print(await Future.wait(fs)); // expect: [0, 1, 2]
  print(await Future.any(fs)); // expect: 0
  final xs = <int Function()>[];
  for (var k = 0; k < 3; k++) {
    await null;
    xs.add(() => k++);
  }
  for (final x in xs) print(x() + x());
  // expect: 1
  // expect: 3
  // expect: 5
  void v() async {
    print('v');
  }

  (v as dynamic)() is Future ? print('future') : print('no');
  // expect: v
  // expect: future
  await (v as dynamic)(); // expect: v
  switch (await one()) {
    case 1:
      print('is one');
    default:
      print('other');
  }
  // expect: is one
  print((await same((1, b: 2))).b); // expect: 2
  final (p, q) = await same((3, 4));
  print(p + q); // expect: 7
  final s = switch (await same('x')) {
    'x' => await same('y'),
    _ => 'z',
  };
  print(s); // expect: y
  assert(await one() == 2);
  if (await one() case final w when w == await one())
    print('when $w'); // expect: when 1
  A? none = sum > 99 ? A() : null;
  print(await none?.inc()); // expect: null
  A na = none ?? await same(A());
  print(na.n); // expect: 0
  na
    ..n = await one()
    ..n += 1;
  print(na.n); // expect: 2
  print(
    await one() == 1 && await same(true) || await same(false),
  ); // expect: true
  print(await same(null) ?? await same('default')); // expect: default
}
