class A {
  final int n;
  const A(this.n);
  const A.other() : this(8);
  const factory A.made(int n) = A;
  static const A k = A(5);
}

const A x = A(1), y = x;
const A? none = null;
void main() {
  number(x.n); // expect: 1
  number(y.n); // expect: 1
  truth(identical(x, y)); // expect: true
  number(const A.other().n); // expect: 8
  number(A.k.n); // expect: 5
  truth(none == null); // expect: true
  number((const A.made(6)).n); // expect: 6
  number((true ? const A(4) : x).n); // expect: 4
  const inner = A(9);
  number(inner.n); // expect: 9
}

void number(int n) => print(n);

void truth(bool b) => print(b);
