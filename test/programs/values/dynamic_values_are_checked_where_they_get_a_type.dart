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

dynamic f(int n) => pick(n);
dynamic nothing() {}
dynamic g = 5;
int h = g;

class P {
  dynamic d;
  int n = f(0);
  P([this.d]);
}

int ret(int n) => f(n);
void take(int n, [double d = 1]) {
  number(n);
  truth(d > 1);
}

Object? top(dynamic d) => d;
void main() {
  show(nothing()); // expect: null
  show(g); // expect: 5
  number(h); // expect: 5
  g = 2.5;
  show(g);
  // expect: double
  // expect: 5
  int x = f(0);
  number(x); // expect: 7
  number(ret(0)); // expect: 7
  take(f(0), f(1));
  // expect: 7
  // expect: true
  try {
    take(f(1));
  } on TypeError {
    print('a');
  }
  // expect: a
  try {
    ret(3);
  } on TypeError {
    print('b');
  }
  // expect: b
  try {
    x = f(1);
  } on TypeError {
    number(x);
  }
  // expect: 7
  try {
    int? y = f(5);
    show(y);
    y = f(2);
  } on TypeError {
    print('c');
  }
  // expect: null
  // expect: c
  final p = P();
  show(p.d); // expect: null
  p.d = A(3);
  show(p.d);
  // expect: A
  // expect: 3
  p.d = 4;
  number(p.n); // expect: 7
  show(top(p.d)); // expect: 4
  A a = P(A(9)).d;
  number(a.n); // expect: 9
  dynamic d = 1;
  d = true;
  if (d) print('yes'); // expect: yes
  bool b = d;
  truth(b); // expect: true
  d = null;
  truth(d == null); // expect: true
  truth(d is Null); // expect: true
  d = B(6);
  if (d is A) number(d.n); // expect: 6
  truth(d == d); // expect: true
  show(d as A);
  // expect: B
  // expect: 6
  d ??= 4;
  show(d);
  // expect: B
  // expect: 6
  Object o = f(3);
  show(o);
  // expect: A
  // expect: 3
  try {
    o = f(5);
  } on TypeError {
    print('d');
  }
  // expect: d
  var v = f(0);
  show(v); // expect: 7
  v = false;
  show(v); // expect: false
}

void number(int n) => print(n);

void truth(bool b) => print(b);
