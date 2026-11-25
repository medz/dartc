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

int? a;
double? b = 1.5;
bool? c;

class P {
  int? n;
  double? d;
  bool? b;
  P([this.n]);
}

int? f(int n) => n > 1 ? n : null;
int orElse(int? n) => n ?? -1;
void main() {
  show(a); // expect: null
  show(b);
  // expect: double
  // expect: 3
  show(c); // expect: null
  a = 3;
  b = null;
  c = true;
  show(a); // expect: 3
  show(b); // expect: null
  show(c); // expect: true
  show(f(0)); // expect: null
  show(f(5)); // expect: 5
  number(orElse(f(1))); // expect: -1
  number(orElse(f(2))); // expect: 2
  final p = P();
  show(p.n); // expect: null
  p.n = 4;
  p.n ??= 5;
  show(p.n); // expect: 4
  p.d ??= 2.5;
  show(p.d);
  // expect: double
  // expect: 5
  show(p.b); // expect: null
  int? x = f(7);
  if (x != null) {
    number(x + 1);
    x++;
    number(x);
  }
  // expect: 8
  // expect: 8
  x ??= 2;
  number(x); // expect: 8
  x = null;
  number(x ?? 9); // expect: 9
  x ??= 3;
  number(x + 1); // expect: 4
  number(f(4)!); // expect: 4
  try {
    number(f(0)!);
  } on TypeError {
    print('null');
  }
  // expect: null
  truth(f(0) == null); // expect: true
  truth(f(3) == 3); // expect: true
  truth(f(3) == 3.0); // expect: true
  truth(f(0) == 0); // expect: false
  truth(null == f(0)); // expect: true
  double? y = yes() ? 2.5 : null;
  if (y is double) truth(y > 2); // expect: true
  truth((y ?? 0) > 1); // expect: true
  bool? z = c;
  if (z == true) print('true'); // expect: true
  if (z!) print('z'); // expect: z
  int? w;
  w = w == null ? 1 : w + 1;
  number(w); // expect: 1
  number(P(3).n ?? 0); // expect: 3
  number((P().n ?? 6) + 1); // expect: 7
  P? q = yes() ? P(8) : null;
  number(q?.n ?? 0); // expect: 8
  q = null;
  show(q?.n); // expect: null
  show(q?.b); // expect: null
}

void number(int n) => print(n);

void truth(bool b) => print(b);
