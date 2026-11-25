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
    any(n);
    number(n);
  } on B {
    return 50;
  } on A catch (e) {
    number(e.n);
  } on C {
    throw D();
  } finally {
    print('f');
  }
  return 60;
}

void main() {
  for (var i = 0; i < 6; i++) {
    try {
      number(f(i));
    } on D {
      print('D');
    } catch (e) {
      print('other');
    }
  }
  // expect: 0
  // expect: f
  // expect: 60
  // expect: 1
  // expect: f
  // expect: 60
  // expect: f
  // expect: 50
  // expect: f
  // expect: D
  // expect: f
  // expect: D
  // expect: 5
  // expect: f
  // expect: 60
}

void number(int n) => print(n);
