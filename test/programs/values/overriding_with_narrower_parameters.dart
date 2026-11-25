class A {
  final int n;
  A(this.n);
}

class B extends A {
  B(super.n);
}

abstract class I {}

class C implements I {
  const C();
}

int zero() => 0;
bool yes() => zero() == 0;

/// Says what any object is.
void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else if (o is bool) {
    truth(o);
  } else if (o is B) {
    print('B');
    number(o.n);
  } else if (o is A) {
    print('A');
    number(o.n);
  } else {
    print('other');
  }
}

Object? pick(int n) {
  switch (n) {
    case 0:
      return 7;
    case 1:
      return 2.5;
    case 2:
      return true;
    case 3:
      return A(3);
    case 4:
      return B(4);
    case 5:
      return null;
    case 6:
      return C();
    case 7:
      return -0.0;
    case 8:
      return false;
    case 9:
      return 0 / 0;
  }
  return 1 << 62;
}

class P {
  void f(covariant A a, [covariant Object o = 1]) {
    print('P');
  }

  covariant A x = A(1);
  num y = 1;
}

class Q extends P {
  @override
  void f(B b, [int n = 2]) {
    print('Q');
    number(b.n + n);
  }

  @override
  B x = B(2);
  @override
  covariant int y = 5;
}

void t(P p, A a, Object o, num n) {
  try {
    p.f(a, o);
  } on TypeError {
    print('a');
  }
  try {
    p.f(a);
  } on TypeError {
    print('b');
  }
  try {
    p.x = a;
    number(p.x.n);
  } on TypeError {
    print('c');
  }
  try {
    p.y = n;
    show(p.y);
  } on TypeError {
    print('d');
  }
}

void main() {
  t(P(), A(3), 4, 1.5);
  // expect: P
  // expect: P
  // expect: 3
  // expect: double
  // expect: 3
  t(Q(), B(5), 6, 7);
  // expect: Q
  // expect: 11
  // expect: Q
  // expect: 7
  // expect: 5
  // expect: 7
  t(Q(), B(5), 1.5, 2.5);
  // expect: a
  // expect: Q
  // expect: 7
  // expect: 5
  // expect: d
  t(Q(), A(5), 6, 7);
  // expect: a
  // expect: b
  // expect: c
  // expect: 7
}

void number(int n) => print(n);

void truth(bool b) => print(b);
