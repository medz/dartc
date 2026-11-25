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

A pick(A? a) => a ?? (throw C());
int choose(bool b) => b ? 1 : throw A(2);
bool both(bool b) => b && (throw D());
Never fail() => throw B(7);
int add(int a, int b) => a + b;
int arrow() => throw A(9);
void main() {
  number(pick(A(4)).n); // expect: 4
  number(choose(true)); // expect: 1
  truth(both(false)); // expect: false
  try {
    pick(null);
  } on C {
    print('C');
  }
  // expect: C
  try {
    choose(false);
  } on A catch (e) {
    number(e.n);
  }
  // expect: 2
  try {
    both(true);
  } on D {
    print('D');
  }
  // expect: D
  try {
    fail();
  } on B catch (e) {
    number(e.n);
  }
  // expect: 7
  try {
    number(arrow());
  } on A catch (e) {
    number(e.n);
  }
  // expect: 9
  try {
    number(add(trace(1), throw A(trace(5))));
  } on A catch (e) {
    number(e.n);
  }
  // expect: 1
  // expect: 5
  // expect: 5
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
