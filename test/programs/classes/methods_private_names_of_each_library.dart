class A {
  int _f() => 1;
  int f() => _f();
}

class B extends A {
  @override
  int _f() => 2;
}

void main() {
  number(A().f()); // expect: 1
  number(B().f()); // expect: 2
}

void number(int n) => print(n);
