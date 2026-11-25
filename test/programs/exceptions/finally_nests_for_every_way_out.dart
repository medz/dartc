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
  var r = 0;
  outer:
  for (var i = 0; i < 3; i++) {
    try {
      try {
        try {
          if (n == 1) return trace(i + 70);
          if (n == 2) break;
          if (n == 3) continue;
          if (n == 4) break outer;
          if (n == 5) raise(5);
          if (n == 6) any(3);
          r += 1;
        } finally {
          print('a');
          r += 10;
          number(i);
        }
      } on A {
        print('A');
      } finally {
        print('b');
      }
    } finally {
      print('c');
      if (n == 7) r *= 2;
    }
  }
  return r;
}

void main() {
  for (var i = 0; i < 8; i++) {
    try {
      number(f(i));
    } on C {
      print('C');
    }
  }
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: a
  // expect: 1
  // expect: b
  // expect: c
  // expect: a
  // expect: 2
  // expect: b
  // expect: c
  // expect: 33
  // expect: 70
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: 70
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: 10
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: a
  // expect: 1
  // expect: b
  // expect: c
  // expect: a
  // expect: 2
  // expect: b
  // expect: c
  // expect: 30
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: 10
  // expect: a
  // expect: 0
  // expect: A
  // expect: b
  // expect: c
  // expect: a
  // expect: 1
  // expect: A
  // expect: b
  // expect: c
  // expect: a
  // expect: 2
  // expect: A
  // expect: b
  // expect: c
  // expect: 30
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: C
  // expect: a
  // expect: 0
  // expect: b
  // expect: c
  // expect: a
  // expect: 1
  // expect: b
  // expect: c
  // expect: a
  // expect: 2
  // expect: b
  // expect: c
  // expect: 154
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
