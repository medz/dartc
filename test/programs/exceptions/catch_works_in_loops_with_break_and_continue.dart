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
  var n = 0;
  while (true) {
    try {
      n++;
      if (n == 2) continue;
      if (n == 7) break;
      raise(n);
    } on A catch (e) {
      if (e.n == 4) continue;
      number(e.n);
      if (n == 6) raise(0);
    }
  }
  // expect: 1
  // expect: 3
  // expect: 5
  // expect: 6
  number(n); // expect: 7
  outer:
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      try {
        raise(i * j);
      } catch (_) {
        if (j == 3) continue outer;
        if (i == 3) break outer;
      }
      number(i * 10 + j);
    }
  }
  // expect: 0
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 10
  // expect: 11
  // expect: 12
  // expect: 20
  // expect: 21
  // expect: 22
  // expect: 30
}

void number(int n) => print(n);
