class A {
  final int n;
  final double d;
  final bool b;
  final A? next;
  const A(this.n, this.d, this.b, [this.next]);
}

class B extends A {
  final int extra;
  final int more = 7;
  const B(int n) : extra = n + 1, super(n * 2, n / 2, n > 3);
  int sum() => n + extra + more;
}

const a = A(1, 2, true, B(5)), a0 = A(0, 0, false);
A orZero(A? a) => a ?? a0;
void main() {
  final b = orZero(a.next), c = orZero(b.next);
  number(a.n); // expect: 1
  truth(a.d == 2.0); // expect: true
  truth(a.b); // expect: true
  number(b.n); // expect: 10
  number(c.n); // expect: 0
  number(const B(5).sum()); // expect: 23
  truth(const B(5).d == 2.5); // expect: true
  truth(const B(5).b); // expect: true
  truth(const B(3).b); // expect: false
}

void number(int n) => print(n);

void truth(bool b) => print(b);
