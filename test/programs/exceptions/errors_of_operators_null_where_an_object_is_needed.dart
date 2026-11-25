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

A? some(bool b) => b ? A(8) : null;
void main() {
  number(some(true)!.n); // expect: 8
  try {
    number(some(false)!.n);
  } on TypeError {
    print('a');
  }
  // expect: a
  final A a = some(true)!;
  number(a.n); // expect: 8
  number(zero()!); // expect: 0
  A? x = some(false);
  try {
    x!;
  } on Error catch (e) {
    print('b');
  }
  // expect: b
  x = A(3);
  number(x.n); // expect: 3
  number(zero()!); // expect: 0
  final B? b = null;
  try {
    print('c');
    raise(b!.n);
  } on TypeError {
    print('d');
  }
  // expect: c
  // expect: d
}

void number(int n) => print(n);
