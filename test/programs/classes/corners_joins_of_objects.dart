class A {
  int n;
  A(this.n);
  int f() => n;
}

class B extends A {
  B(super.n);
  @override
  int f() => n * 10;
}

A pick(bool b, A x, A y) => b ? x : y;
void main() {
  A a = A(1), b = B(2);
  A? c;
  for (var i = 0; i < 4; i++) {
    final t = a;
    a = b;
    b = t;
    number(a.f());
    if (i > 1) c = a;
  }
  // expect: 20
  // expect: 1
  // expect: 20
  // expect: 1
  if (c != null) number(c.f()); // expect: 1
  number(pick(1 < 2, a, b).f()); // expect: 1
  number(pick(1 > 2, a, b).f()); // expect: 20
}

void number(int n) => print(n);
