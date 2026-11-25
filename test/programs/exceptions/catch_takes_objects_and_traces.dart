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

void main() {
  final a = A(3);
  try {
    throw a;
  } catch (e, s) {
    truth(identical(e, a));
    truth(e == a);
    truth(s == s);
    final StackTrace t = s;
    truth(identical(s, t));
  }
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  try {
    throw a;
  } on Object catch (e, _) {
    truth(e == a);
  }
  // expect: true
  try {
    throw a;
  } on A catch (e) {
    number(e.n);
    A b = e;
    b = B(4);
    number(b.n);
  }
  // expect: 3
  // expect: 4
}

void number(int n) => print(n);

void truth(bool b) => print(b);
