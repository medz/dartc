abstract class S {
  int get k;
  int f(int a, [int b = 1]);
}

class A implements S {
  @override
  int k = 1;
  @override
  int f(int a, [int b = 2, int c = 3]) => a + b + c;
}

class B implements S {
  @override
  int get k => 2;
  @override
  int f(int a, [int b = 4]) => a * b;
}

class C extends B {
  @override
  int get k => super.k + 10;
}

class D extends A {
  @override
  int f(int a, [int b = 9, int c = 8]) => super.f(a, b) - c;
}

class E implements S {
  final S s;
  E(this.s);
  @override
  int get k => s.k * 2;
  @override
  int f(int a, [int b = 5]) => s.f(a, b) + s.f(a);
}

void use(S s) {
  number(s.k);
  number(s.f(3));
  number(s.f(3, 6));
}

void main() {
  use(A());
  // expect: 1
  // expect: 8
  // expect: 12
  use(B());
  // expect: 2
  // expect: 12
  // expect: 18
  use(C());
  // expect: 12
  // expect: 12
  // expect: 18
  use(D());
  // expect: 1
  // expect: 7
  // expect: 4
  use(E(D()));
  // expect: 2
  // expect: 10
  // expect: 11
  use(E(E(C())));
  // expect: 48
  // expect: 54
  // expect: 57
}

void number(int n) => print(n);
