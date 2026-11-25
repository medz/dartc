import 'dart:collection' as col;

int top = 0;

class H {
  static int s = 0;
  int f = 0;
  late int lf;
}

int get g => top;
set g(int v) => top = v * 2;
T id<T>(T x) => x;

class Call {
  T call<T>(T x, {int n = 1}) => x;
}

class Nsm {
  noSuchMethod(i) => i.memberName;
}

void main() {
  for (top in [1, 2]) print(top);
  // expect: 1
  // expect: 2
  for (g in [5]) print(top); // expect: 10
  top = 12;
  dynamic d;
  for (d in [1, 'a']) print(d);
  // expect: 1
  // expect: a
  num n;
  for (n in <int>[1]) print(n + 1); // expect: 2
  final c = Call();
  print(c('x')); // expect: x
  print(c<int>(3, n: 2)); // expect: 3
  int Function(int) f = c.call;
  print(f(4)); // expect: 4
  int Function(int) f2 = c;
  print(f2(5)); // expect: 5
  final List<Object? Function()> fs = [() => null, main2];
  print(fs.length); // expect: 2
  print(id<int Function(int)>(id)(3)); // expect: 3
  a:
  {
    if (top > 1) break a;
    print('no');
  }
  do {
    if (top++ > 14) continue;
  } while (top < 18);
  print(top); // expect: 18
  print([
    for (var i = 0; i < 3; i++)
      if (i.isOdd) i else ...[i, i],
  ]); // expect: [0, 0, 1, 2, 2]
  print({
    for (final e in {'a': 1}.entries) e.value: e.key,
  }); // expect: {1: a}
  int? q;
  print([?q, ?top]); // expect: [18]
  print({'k': ?q}); // expect: {}
  var (x, y) = (1, 2);
  x ^= 3;
  y <<= 2;
  x ??= 4;
  print('$x $y'); // expect: 2 8
  String s =
      'a'
      'b'
      "c";
  print(s); // expect: abc
  print(r'\n$x'); // expect: \n$x
  print(0x1F + 1_000); // expect: 1031
  print(1e3); // expect: 1000.0
  print('\u{1F600}'.length); // expect: 2
  assert(() {
    print('never');
    return true;
  }());
  var i = 0;
  i = i++ + ++i;
  print(i); // expect: 2
  print(i is! int); // expect: false
  print(-5 ~/ 2); // expect: -2
  print(-5 % 3); // expect: 1
  print(5.remainder(-3)); // expect: 2
  print(7 >>> 1); // expect: 3
  final z = <int>[]
    ..add(1)
    ..addAll([2]);
  print(z); // expect: [1, 2]
  Object o = 3;
  if (o is int && o.isOdd) print('odd'); // expect: odd
  if (o is! String) print('ns'); // expect: ns
  print(o as num); // expect: 3
  col.Queue<int> qu = col.Queue()..add(3);
  print(qu.first); // expect: 3
  print((Nsm() as dynamic).foo); // expect: Symbol("foo")
  external1();
  // expect: sx
  // expect: f
  late String l;
  l = 'late';
  print(l); // expect: late
  print(const <String>{'a'}.contains('a')); // expect: true
  print(#foo.bar); // expect: Symbol("foo.bar")
  print(1.toString().codeUnits); // expect: [49]
  covariantTest();
  // expect: type 'double' is not a subtype of type 'int' of 'n'
  // expect: B1
  switch (o) {
    case 1 || 2:
      print('small');
    case int k when k > 2:
      print('k $k');
    default:
  }
  // expect: k 3
  void inner<T extends num>([T? a, int b = 2]) => print('$T $a $b');
  inner<int>(1); // expect: int 1 2
  inner(2.5, 3); // expect: double 2.5 3
  inner(); // expect: num null 2
  print(identical(id, id)); // expect: true
  print(Call().runtimeType == Call); // expect: true
  throwing();
  // expect: q
  // expect: 1
}

Object? main2() => 1;
void external1() {
  try {
    throw 'x';
  } on String catch (e) {
    print('s$e');
  } on Object catch (e, t) {
    print(t);
  } finally {
    print('f');
  }
}

class A {
  void m(covariant num n) => print(n);
}

class B extends A {
  void m(int n) => print('B$n');
}

void covariantTest() {
  A a = B();
  try {
    a.m(1.5);
  } catch (e) {
    print(e);
  }
  a.m(1);
}

Never fail(String s) => throw StateError(s);
void throwing() {
  try {
    fail('q');
  } on StateError catch (e) {
    print(e.message);
  }
  final int v = DateTime.now().year > 1 ? 1 : fail('z');
  print(v);
}
