abstract class A {
  abstract int n;
  void f() => print('A');
  int g();
}

abstract class B extends A {
  @override
  void f();
  @override
  int g() => n * 2;
}

class C extends B {
  @override
  int n = 4;
}

class D extends B {
  @override
  int get n => 6;
  @override
  set n(int v) => number(v);
  @override
  void f() {
    super.f();
    print('D');
  }
}

void use(A a) {
  a.f();
  number(a.g());
  a.n += 1;
  number(a.n);
}

void main() {
  use(C());
  // expect: A
  // expect: 8
  // expect: 5
  use(D());
  // expect: A
  // expect: D
  // expect: 12
  // expect: 7
  // expect: 6
}

void number(int n) => print(n);
