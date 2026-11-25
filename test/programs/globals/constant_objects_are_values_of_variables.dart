class A {
  final int n;
  const A(this.n);
}

const k = A(3);
A a = const A(1);
final A b = k;
A? c = const A(2);

class S {
  static A s = const A(1);
}

void main() {
  number(a.n); // expect: 1
  number(b.n); // expect: 3
  truth(identical(a, S.s)); // expect: true
  truth(c != null); // expect: true
  a = b;
  number(a.n); // expect: 3
  S.s = k;
  truth(identical(S.s, a)); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
