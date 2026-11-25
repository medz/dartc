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

double inf = 1 / 0, nan = 0 / 0;
void t(double d) {
  try {
    number(d.toInt());
  } on UnsupportedError {
    print('u');
  }
  try {
    number(d ~/ 2);
  } on UnsupportedError {
    print('v');
  }
  try {
    number(d ~/ zero());
  } on UnsupportedError {
    print('w');
  }
  try {
    number(5 ~/ d);
  } on Error {
    print('x');
  }
}

void main() {
  t(0);
  // expect: 0
  // expect: 0
  // expect: w
  // expect: x
  t(-0.0);
  // expect: 0
  // expect: 0
  // expect: w
  // expect: x
  t(2.5);
  // expect: 2
  // expect: 1
  // expect: w
  // expect: 2
  t(-7.9);
  // expect: -7
  // expect: -3
  // expect: w
  // expect: 0
  t(1e300);
  // expect: 9223372036854775807
  // expect: 9223372036854775807
  // expect: w
  // expect: 0
  t(-1e300);
  // expect: -9223372036854775808
  // expect: -9223372036854775808
  // expect: w
  // expect: 0
  t(inf);
  // expect: u
  // expect: v
  // expect: w
  // expect: 0
  t(-inf);
  // expect: u
  // expect: v
  // expect: w
  // expect: 0
  t(nan);
  // expect: u
  // expect: v
  // expect: w
  // expect: x
  t(9223372036854774784.0);
  // expect: 9223372036854774784
  // expect: 4611686018427387392
  // expect: w
  // expect: 0
  t(9223372036854775808.0);
  // expect: 9223372036854775807
  // expect: 4611686018427387904
  // expect: w
  // expect: 0
  t(-9223372036854775808.0);
  // expect: -9223372036854775808
  // expect: -4611686018427387904
  // expect: w
  // expect: 0
  number(7.toInt()); // expect: 7
  var i = 9;
  i ~/= 2.5;
  number(i); // expect: 3
  number((0.1 + 0.2).toInt()); // expect: 0
}

void number(int n) => print(n);
