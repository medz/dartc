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

A? f(int n) {
  if (n > 0) return A(n);
}

Object? g(bool b) {
  if (b) return 1;
}

int? h(int n) {
  while (n < 10) {
    n++;
  }
}

dynamic k(bool b) {
  if (b) return true;
}

void main() {
  truth(f(0) == null); // expect: true
  number(f(2)!.n); // expect: 2
  show(g(true)); // expect: 1
  show(g(false)); // expect: null
  show(h(3)); // expect: null
  show(k(true)); // expect: true
  show(k(false)); // expect: null
}

void number(int n) => print(n);

void truth(bool b) => print(b);
