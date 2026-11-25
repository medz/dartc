class A {
  final int n;
  const A(this.n) : assert(n > 0);
}

const A k = A(1 + 2 * 3);
const bool yes = identical(k, const A(7));
void main() {
  number(k.n); // expect: 7
  truth(yes); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
