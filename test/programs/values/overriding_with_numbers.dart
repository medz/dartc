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
  Object f(int n) => n;
  Object? g;
  Object get h => 1.5;
  num k(double d) => d;
  void w(int n) {
    number(n);
  }

  Object? z(A a) => a;
  num i = 1;
  bool operator <(A a) => false;
}

class Q extends P {
  @override
  int f(Object n) {
    show(n);
    return 8;
  }

  @override
  double get h => 2.5;
  @override
  int k(num d) => 3;
  @override
  void w(num n) {
    show(n);
  }

  @override
  int? z(Object? a) => a is int ? a : null;
}

class R implements P {
  @override
  A f(num n) => A(n is int ? n : 0);
  @override
  Object? g = 4;
  @override
  int h = 6;
  @override
  double k(Object? d) => 2.5;
  @override
  void w(Object? n, [int m = 3]) {
    show(n);
    number(m);
  }

  @override
  B? z(A? a) => null;
  @override
  num i = 2.5;
  @override
  bool operator <(Object o) => true;
}

void use(P p) {
  show(p.f(5));
  show(p.g);
  p.g = 3;
  show(p.g);
  show(p.h);
  show(p.k(0.5));
  p.w(4);
  show(p.z(A(1)));
  show(p.i);
  p.i = 7;
  show(p.i);
  p.i++;
  show(p.i);
  truth(p < A(1));
}

void main() {
  use(P());
  // expect: 5
  // expect: null
  // expect: 3
  // expect: double
  // expect: 3
  // expect: double
  // expect: 1
  // expect: 4
  // expect: A
  // expect: 1
  // expect: 1
  // expect: 7
  // expect: 8
  // expect: false
  use(Q());
  // expect: 5
  // expect: 8
  // expect: null
  // expect: 3
  // expect: double
  // expect: 5
  // expect: 3
  // expect: 4
  // expect: null
  // expect: 1
  // expect: 7
  // expect: 8
  // expect: false
  use(R());
  // expect: A
  // expect: 5
  // expect: 4
  // expect: 3
  // expect: 6
  // expect: double
  // expect: 5
  // expect: 4
  // expect: 3
  // expect: null
  // expect: double
  // expect: 5
  // expect: 7
  // expect: 8
  // expect: true
  number(Q().f(1.5));
  // expect: double
  // expect: 3
  // expect: 8
  truth(Q().h > 2); // expect: true
  number(R().h); // expect: 6
}

void number(int n) => print(n);

void truth(bool b) => print(b);
