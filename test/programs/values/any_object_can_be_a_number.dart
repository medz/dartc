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

Object field = 5;

class P {
  Object o = 1;
  Object? p;
  P(this.p);
  Object get g => 2.5;
  set g(Object? v) {
    p = v;
  }
}

Object same(Object o) => o;
Object? maybe([Object? o = 8]) => o;
void main() {
  show(1); // expect: 1
  show(2.5);
  // expect: double
  // expect: 5
  show(true); // expect: true
  show(null); // expect: null
  show(A(4));
  // expect: A
  // expect: 4
  for (var i = 0; i < 11; i++) show(pick(i));
  // expect: 7
  // expect: double
  // expect: 5
  // expect: true
  // expect: A
  // expect: 3
  // expect: B
  // expect: 4
  // expect: null
  // expect: other
  // expect: double
  // expect: 0
  // expect: false
  // expect: double
  show(same(3));
  show(field);
  field = false;
  show(field);
  final p = P(6);
  show(p.o);
  show(p.p);
  show(p.g);
  p.g = 9;
  show(p.p);
  p.o = 3.5;
  show(p.o);
  show(maybe());
  show(maybe(null));
  show(maybe(true));
  Object o = yes() ? 1 : A(2);
  show(o);
  o = 1.5;
  show(o);
  show(o = 4);
  Object x = 1;
  number((x = 5) + 2);
  show(x);
}

void number(int n) => print(n);

void truth(bool b) => print(b);
// stderr: Unhandled exception:
// stderr: Unsupported operation: Infinity or NaN toInt
// exit: 255
