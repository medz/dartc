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

void f(int n) {
  try {
    raise(n);
  } finally {
    try {
      any(3);
    } on C {
      print('C');
    } finally {
      print('in');
    }
    for (var i = 0; i < 2; i++) {
      try {
        raise(i);
      } catch (_) {
        continue;
      } finally {
        number(i);
      }
    }
  }
  print('end');
}

void main() {
  f(0);
  // expect: C
  // expect: in
  // expect: 0
  // expect: 1
  // expect: end
  try {
    f(1);
  } on A {
    print('A');
  }
  // expect: C
  // expect: in
  // expect: 0
  // expect: 1
  // expect: A
}

void number(int n) => print(n);
