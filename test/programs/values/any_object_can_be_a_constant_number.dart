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

const Object i = 5, d = 2.5, b = true;
const Object? n = null;
const num m = 4;
const int? k = 6;

class K {
  final Object o;
  final num? n;
  const K(this.o, [this.n]);
}

void f([Object o = 3, num n = 2.5, int? i = 7, Object? z]) {
  show(o);
  show(n);
  show(i);
  show(z);
}

Object g = 1;
num h = -2;
double? j = -0;
final Object l = false;
void main() {
  show(i); // expect: 5
  show(d);
  // expect: double
  // expect: 5
  show(b); // expect: true
  show(n); // expect: null
  show(m); // expect: 4
  show(k); // expect: 6
  show(const K(1).o); // expect: 1
  show(const K(1.5, 3).n); // expect: 3
  show(const K(true).n); // expect: null
  truth(identical(const K(1), const K(1))); // expect: true
  truth(identical(const K(1), const K(1.0))); // expect: false
  truth(identical(const K(0.0), const K(-0.0))); // expect: false
  f();
  // expect: 3
  // expect: double
  // expect: 5
  // expect: 7
  // expect: null
  f(A(1), 1);
  // expect: A
  // expect: 1
  // expect: 1
  // expect: 7
  // expect: null
  show(g); // expect: 1
  show(h); // expect: -2
  show(l); // expect: false
  truth(1 / (j ?? 1) < 0); // expect: true
  truth(identical(i, 5)); // expect: true
  truth(const K(true).o == true); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
