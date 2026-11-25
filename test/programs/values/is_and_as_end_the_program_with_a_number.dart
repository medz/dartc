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

class Q extends A {
  Q(super.n);
}

class P {
  A? f;
}

class R extends P {
  @override
  covariant B? f;
}

class S {
  void up(covariant A a) {}
}

class T extends S {
  @override
  void up(B b) {}
}

void main() {
  print('a'); // expect: a
  pick(0) as A;
}

void number(int n) => print(n);

void truth(bool b) => print(b);
// stderr: Unhandled exception:
// stderr: type 'int' is not a subtype of type 'A' in type cast
// exit: 255
