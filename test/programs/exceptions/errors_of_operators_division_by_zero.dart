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
  var x = 7;
  try {
    x ~/ z;
  } on IntegerDivisionByZeroException {
    print('a');
  }
  // expect: a
  try {
    x % z;
  } on UnsupportedError {
    print('b');
  }
  // expect: b
  try {
    x ~/= z;
  } on Exception {
    print('c');
  }
  // expect: c
  try {
    x %= 0;
  } on Error {
    print('d');
  }
  // expect: d
  number(x); // expect: 7
  number(x ~/ (z + 2)); // expect: 3
  number(-7 % (z - 3)); // expect: 2
  number(7 % (z - 3)); // expect: 1
  number(x ~/ (z - 1)); // expect: -7
  number(-9223372036854775808 % (z - 1)); // expect: 0
  number(-9223372036854775808 ~/ (z - 1)); // expect: -9223372036854775808
  number(-7 % (z - 9223372036854775807 - 1)); // expect: 9223372036854775801
}

void number(int n) => print(n);
