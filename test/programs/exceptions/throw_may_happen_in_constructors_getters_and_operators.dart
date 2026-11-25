class A {
  final int n;
  A(this.n);
}

class B extends A {
  B(super.n);
}

class C implements Exception {
  const C();
}

class D extends Error {}

abstract class I {}

class J extends A implements I {
  J(super.n);
}

int raise(int n) {
  if (n > 0) throw A(n);
  return n;
}

void any(int n) {
  switch (n) {
    case 1:
      throw A(1);
    case 2:
      throw B(2);
    case 3:
      throw C();
    case 4:
      throw D();
    case 5:
      throw J(5);
    case 6:
      throw const C();
  }
}

int zero() => 0;
A? none() => null;

class P {
  int x;
  int y = raise(zero());
  P(this.x) {
    if (x > 2) throw A(x);
  }
  int get z => x > 1 ? throw A(10 + x) : x;
  set z(int v) {
    if (v > 1) throw A(20 + v);
    x = v;
  }

  P operator +(P o) => throw A(30 + o.x);
  bool operator ==(Object o) => throw A(40);
}

void t(int n) {
  try {
    final p = P(n);
    switch (n) {
      case 0:
        p.z = 1;
        number(p.z);
        p.z = 9;
      case 1:
        p + p;
      case 2:
        p.z;
    }
    number(p == p ? 1 : 0);
  } on A catch (e) {
    number(e.n);
  }
}

void main() {
  t(0);
  // expect: 1
  // expect: 29
  t(1); // expect: 31
  t(2); // expect: 12
  t(3); // expect: 3
}

void number(int n) => print(n);
