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
  try {
    int v;
    if (zero() == 0) {
      v = 1;
    } else {
      v = 2;
    }
    number(v);
  } finally {
    number(3);
    int w;
    w = 4;
    number(w);
  }
  // expect: 1
  // expect: 3
  // expect: 4
  for (var i = 0; i < 2; i++) {
    try {
      var v = i;
      v++;
      raise(i);
      number(v);
    } on A catch (e) {
      var v = 5;
      v += e.n;
      number(v);
    } finally {
      var v = 6;
      v--;
      number(v);
    }
  }
  // expect: 1
  // expect: 5
  // expect: 6
  // expect: 5
}

void number(int n) => print(n);
