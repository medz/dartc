void f() => 3;
void g(int n) {
  if (n > 1) return;
  print('g');
}

class A {
  void m() {}
  void n() => 'A';
  set s(int v) => v * 2;
  void operator []=(int i, int v) => v;
}

class B extends A {
  int m() => 5;
  void n() => super.n();
}

void h<T>(T x) => x;
void each(void Function(int) w) {
  dynamic d = w;
  print(d(4));
}

Object? pass(void Function() w) => (w as dynamic)();
void main() {
  dynamic d = f;
  print(d()); // expect: 3
  d = g;
  print(d(1));
  // expect: g
  // expect: null
  print(d(2)); // expect: null
  A a = B();
  d = a;
  print(d.m()); // expect: 5
  print(d.n()); // expect: A
  print(A().runtimeType); // expect: A
  d = A();
  print(d.n()); // expect: A
  print(d.s = 3); // expect: 3
  print(d[0] = 4); // expect: 4
  d = h;
  print(d<int>(7)); // expect: 7
  print(d('x')); // expect: x
  each((n) => n + 1); // expect: 5
  each((n) {}); // expect: null
  print(pass(f)); // expect: 3
  print(pass(() => 'c')); // expect: c
  print(pass(a.m)); // expect: 5
  print(pass(a.n)); // expect: A
  final List<void> l = [1, 2];
  print(l); // expect: [1, 2]
  void v = 3;
  Object? o = [v].first as Object?;
  print(o); // expect: 3
  print([f].map((x) => x as dynamic).first()); // expect: 3
  [1].forEach((e) => e);
  a
    ..m()
    ..n();
  void local() => 9;
  print(pass(local)); // expect: 9
  d is Function ? f() : g(3);
  print(Function.apply(f, [])); // expect: 3
}
