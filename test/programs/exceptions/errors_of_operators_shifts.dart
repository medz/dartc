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
  final z = zero();
  try {
    1 << (z - 1);
  } on ArgumentError {
    print('a');
  }
  // expect: a
  try {
    1 >> (z - 5);
  } on Error {
    print('b');
  }
  // expect: b
  try {
    1 >>> -1;
  } on ArgumentError {
    print('c');
  }
  // expect: c
  number(1 << (z + 5)); // expect: 32
  number(1 << (z + 63)); // expect: -9223372036854775808
  number(1 << (z + 64)); // expect: 0
  number(-9 >> (z + 2)); // expect: -3
  number(-9 >> (z + 63)); // expect: -1
  number(-9 >> (z + 64)); // expect: -1
  number(-9 >> (z + 9223372036854775807)); // expect: -1
  number(9 >> (z + 100)); // expect: 0
  number(-9 >>> (z + 60)); // expect: 15
  number(-9 >>> (z + 64)); // expect: 0
  number(9 >>> (z + 1)); // expect: 4
  var x = 3;
  x <<= z + 2;
  x >>= z + 1;
  x >>>= z;
  number(x); // expect: 6
}

void number(int n) => print(n);
