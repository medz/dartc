class A {
  int f(int x) => x + 1;
  int g(int x) => f(x) * 10;
}

class B extends A {
  @override
  int f(int x) => super.f(x) + 2;
}

class C extends B {
  @override
  int f(int x) => super.f(x) * super.g(1) ~/ 10;
}

void use(A a) {
  number(a.f(3));
  number(a.g(3));
}

void main() {
  use(A());
  // expect: 4
  // expect: 40
  use(B());
  // expect: 6
  // expect: 60
}

void number(int n) => print(n);
