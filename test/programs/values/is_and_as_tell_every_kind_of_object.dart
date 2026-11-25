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
    final o = pick(i);
    truth(o is int);
    truth(o is double);
    truth(o is num);
    truth(o is bool);
    truth(o is A);
    truth(o is B);
    truth(o is I);
    truth(o is C);
    truth(o is Object);
    truth(o is Object?);
    truth(o is int?);
    truth(o is A?);
    truth(o is Null);
    truth(o is dynamic);
    truth(o is! num);
    truth(o is! A?);
    truth(o is Error);
  }
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
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
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
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
  // expect: true
  // expect: true
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
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
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
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
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
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
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
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
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
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  truth(1 is int); // expect: true
  truth(1 is num); // expect: true
  truth(1 is double); // expect: false
  truth(1.5 is Object); // expect: true
  truth(1 is A); // expect: false
  truth(trace(5) is int);
  // expect: 5
  // expect: true
  A a = B(1);
  truth(a is B); // expect: true
  truth(a is! I); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
