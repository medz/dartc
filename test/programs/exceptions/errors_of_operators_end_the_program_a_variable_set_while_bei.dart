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

int n = 0;
int f() => ++n == 1 ? x + 1 : 5;
final int x = f();

class S {
  static final int y = g();
  static int g() => ++n == 4 ? y + 1 : 5;
}

void main() {
  print('a'); // expect: a
  try {
    number(x);
  } on Error {
    print('E');
  }
  // expect: E
  number(x); // expect: 5
  number(n); // expect: 2
  n = 3;
  number(S.y);
}

void number(int n) => print(n);
// stderr: Unhandled exception:
// stderr: LateInitializationError: Field 'y' has been assigned during initialization.
// exit: 255
