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
  var a = 1, b = 2.5;
  var c = true;
  A? d;
  int e;
  try {
    a = 2;
    raise(0);
    b = 3.5;
    d = A(a);
    a = raise(5);
    c = false;
  } on A catch (x) {
    number(a);
    truth(b == 3.5);
    truth(c);
    number(x.n);
    a += 10;
  }
  // expect: 2
  // expect: true
  // expect: true
  // expect: 5
  number(a); // expect: 12
  truth(d != null); // expect: true
  for (var i = 0; i < 5; i++) {
    try {
      a = i;
      if (i == 3) raise(i);
      b = b + 1;
    } catch (_) {
      a = -a;
    }
    number(a);
  }
  // expect: 0
  // expect: 1
  // expect: 2
  // expect: -3
  // expect: 4
  truth(b == 7.5); // expect: true
  e = 4;
  try {
    e = raise(1);
  } catch (_) {}
  number(e); // expect: 4
}

void number(int n) => print(n);

void truth(bool b) => print(b);
