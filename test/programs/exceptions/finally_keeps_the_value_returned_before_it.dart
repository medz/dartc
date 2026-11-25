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

int x = 1;
int f() {
  var r = 5;
  try {
    return r;
  } finally {
    r = 6;
    x = 2;
  }
}

double g() {
  try {
    return 2.5;
  } finally {
    x++;
  }
}

bool h() {
  try {
    return x > 2;
  } finally {
    x = 0;
  }
}

A k() {
  final a = A(x);
  try {
    return a;
  } finally {
    x = 9;
  }
}

void v() {
  try {
    return;
  } finally {
    print('v');
  }
}

void main() {
  number(f()); // expect: 5
  truth(g() == 2.5); // expect: true
  truth(h()); // expect: true
  number(k().n); // expect: 0
  v(); // expect: v
  number(x); // expect: 9
}

void number(int n) => print(n);

void truth(bool b) => print(b);
