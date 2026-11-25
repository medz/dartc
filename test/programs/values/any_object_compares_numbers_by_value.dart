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

void main() {
  for (var i = 0; i < 11; i++) {
    for (var j = 0; j < 11; j++) {
      final a = pick(i), b = pick(j);
      truth(a == b);
      truth(a != b);
      truth(identical(a, b));
    }
    final o = pick(i);
    truth(o == 7);
    truth(7 == o);
    truth(o == 2.5);
    truth(2.5 == o);
    truth(o == true);
    truth(o != null);
    truth(identical(o, 7));
    truth(0.0 == o);
  }
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  Object a = 7, b = 7.0;
  truth(a == b); // expect: true
  truth(b == a); // expect: true
  truth(identical(a, b)); // expect: false
  truth(identical(0.0, -0.0)); // expect: false
  truth(identical(0 / 0, 0 / 0)); // expect: true
  truth(identical(1, 1)); // expect: true
  truth(identical(true, yes())); // expect: true
  truth(identical(a, 3 + 4)); // expect: true
  truth(1 == 1.0); // expect: true
  Object c = 9007199254740993, d = 9007199254740992.0;
  truth(c == d); // expect: true
  num n = 3, m = 3.0;
  truth(n == m); // expect: true
  truth(identical(n, m)); // expect: false
  truth(n == 3); // expect: true
  truth(a == 7.0); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
