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
  dynamic f() => 1;
  dynamic get g => 2.5;
  void h() {}
  dynamic operator [](dynamic i) => i;
}

class Q extends P {
  @override
  int f() => 2;
  @override
  A get g => A(3);
  @override
  dynamic h() => 7;
  @override
  int operator [](Object? i) => 5;
}

void use(P p) {
  show(p.f());
  show(p.g);
  p.h();
  show(p[4]);
}

void main() {
  use(P());
  // expect: 1
  // expect: double
  // expect: 5
  // expect: 4
  use(Q());
  // expect: 2
  // expect: A
  // expect: 3
  // expect: 5
  number(Q().f()); // expect: 2
  show(Q()[null]); // expect: 5
  if (yes()) return;
}

void number(int n) => print(n);

void truth(bool b) => print(b);
