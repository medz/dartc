class A {
  void f() => print('A');
}

class B extends A {
  @override
  int f() {
    print('B');
    return 4;
  }
}

class C extends B {
  @override
  int f() => super.f() + 1;
}

void use(A a) => a.f();
void main() {
  use(A()); // expect: A
  use(B()); // expect: B
  use(C()); // expect: B
  number(B().f());
  // expect: B
  // expect: 4
  number(C().f());
  // expect: B
  // expect: 5
}

void number(int n) => print(n);
