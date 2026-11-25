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

int size(Object? o) {
  if (o is int) return o + 1;
  if (o is! A) return -1;
  return o.n;
}

int both(Object a, Object b) => a is int && b is int
    ? a * b
    : a is A && b is A
    ? a.n + b.n
    : 0;
void main() {
  for (var i = 0; i < 6; i++) number(size(pick(i)));
  // expect: 8
  // expect: -1
  // expect: -1
  // expect: 3
  // expect: 4
  // expect: -1
  number(both(3, 4)); // expect: 12
  number(both(A(5), B(6))); // expect: 11
  number(both(1, A(1))); // expect: 0
  Object o = 1;
  while (o is int) {
    if (o > 5) {
      o = A(o);
    } else {
      o = o + 2;
    }
  }
  show(o);
  // expect: A
  // expect: 7
  num n = 3;
  if (n is double) {
    print('no');
  } else {
    n as int;
    number(n << 1);
  }
  // expect: 6
}

void number(int n) => print(n);

void truth(bool b) => print(b);
