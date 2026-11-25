class A {
  int n = 3;
}

class B extends A {}

class C {
  int a, b;
  C([this.a = 1, this.b = 2]);
  C.named({this.a = 3, required this.b});
}

class D extends C {
  D([super.a, super.b]);
  D.n({super.a, required super.b}) : super.named();
}

void show(C c) {
  number(c.a);
  number(c.b);
}

void main() {
  number(B().n); // expect: 3
  show(C());
  // expect: 1
  // expect: 2
  show(C(7));
  // expect: 7
  // expect: 2
  show(C(7, 8));
  // expect: 7
  // expect: 8
  show(C.named(b: 4));
  // expect: 3
  // expect: 4
  show(C.named(b: 5, a: 6));
  // expect: 6
  // expect: 5
  show(D());
  // expect: 1
  // expect: 2
  show(D(9));
  // expect: 9
  // expect: 2
  show(D.n(b: 1));
  // expect: 3
  // expect: 1
  show(D.n(b: 1, a: 2));
  // expect: 2
  // expect: 1
}

void number(int n) => print(n);
