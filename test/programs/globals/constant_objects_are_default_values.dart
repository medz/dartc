class A {
  final int n;
  const A(this.n);
}

class B extends A {
  final A other;
  const B(super.n, {this.other = const A(3)});
}

const k = A(4);
int f([A a = const A(1), A? b, A c = k]) =>
    a.n * 100 + (b ?? const A(2)).n * 10 + c.n;

class M {
  int f({A a = const A(6)}) => a.n;
}

class N extends M {
  int f({A a = const A(7), A b = k}) => a.n + b.n;
}

int use(M m) => m.f();

class P {
  final A a;
  P([this.a = const A(8)]);
}

class Q extends P {
  Q([super.a]);
}

class R extends Q {
  R([super.a = k]);
}

class T extends R {
  T([super.a]);
}

void main() {
  number(f()); // expect: 124
  number(f(const A(5))); // expect: 524
  number(f(k, k, k)); // expect: 444
  number(B(1).other.n); // expect: 3
  number(const B(1).other.n); // expect: 3
  number(Q().a.n); // expect: 8
  number(R().a.n); // expect: 4
  number(T().a.n); // expect: 4
  number(use(M())); // expect: 6
  number(use(N())); // expect: 11
}

void number(int n) => print(n);
