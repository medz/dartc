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

int f(int n) {
  try {
    return raise(n) + 100;
  } on A catch (e) {
    return e.n;
  }
}

int g(int n) {
  try {
    if (n > 2) return 1;
    any(n);
  } catch (e) {
    return 2;
  }
  return 3;
}

void main() {
  number(f(0)); // expect: 100
  number(f(6)); // expect: 6
  for (var i = 0; i < 5; i++) number(g(i));
  // expect: 3
  // expect: 2
  // expect: 2
  // expect: 1
  // expect: 1
}

void number(int n) => print(n);
