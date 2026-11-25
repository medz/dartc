class A {
  int x = 1;
}

class B extends A {
  @override
  set x(int v) {
    number(v);
    super.x = v * 2;
  }
}

class C extends B {
  @override
  int get x => super.x + 100;
}

void use(A a) {
  a.x = 5;
  number(a.x);
  a.x++;
  number(a.x);
}

void main() {
  use(A());
  // expect: 5
  // expect: 6
  use(B());
  // expect: 5
  // expect: 10
  // expect: 11
  // expect: 22
  use(C());
  // expect: 5
  // expect: 110
  // expect: 111
  // expect: 322
}

void number(int n) => print(n);
