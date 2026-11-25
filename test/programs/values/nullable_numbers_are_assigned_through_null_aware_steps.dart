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

int? n;
int calls = 0;
int next() => ++calls;
void main() {
  number(n ??= next()); // expect: 1
  number(n ??= next()); // expect: 1
  number(calls); // expect: 1
  n = null;
  final int? r = (n ??= null);
  show(r); // expect: null
  Object? o;
  show(o ??= 5); // expect: 5
  show(o ??= 6); // expect: 5
  num? m;
  m ??= 2;
  m = m + 1;
  show(m); // expect: 3
}

void number(int n) => print(n);

void truth(bool b) => print(b);
