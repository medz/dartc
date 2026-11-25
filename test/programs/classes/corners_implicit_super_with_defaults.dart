class A {
  final int n;
  A([this.n = 3]);
  A.named({this.n = 4});
}

class B extends A {}

class C extends A {
  C();
  C.named({super.n}) : super.named();
  C.pos([super.n]);
  C.other([super.n = 9]);
}

void main() {
  number(B().n); // expect: 3
  number(C().n); // expect: 3
  number(C.named().n); // expect: 4
  number(C.named(n: 1).n); // expect: 1
  number(C.pos().n); // expect: 3
  number(C.pos(2).n); // expect: 2
  number(C.other().n); // expect: 9
}

void number(int n) => print(n);
