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

int tries = 0;
int x = f();
int f() {
  if (++tries < 3) throw A(tries);
  return 40 + tries;
}

void main() {
  for (var i = 0; i < 4; i++) {
    try {
      number(x);
    } on A catch (e) {
      number(-e.n);
    }
  }
  // expect: -1
  // expect: -2
  // expect: 43
  // expect: 43
  number(tries); // expect: 3
}

void number(int n) => print(n);
