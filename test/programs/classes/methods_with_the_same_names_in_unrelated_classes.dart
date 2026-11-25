class A {
  int f(int x) => x;
  int n = 1;
}

class B {
  double f(double x) => x;
  double n = 2.5;
}

class C {
  void f() => print('C');
  bool n = true;
}

void main() {
  number(A().f(3)); // expect: 3
  truth(B().f(1.5) == 1.5); // expect: true
  C().f(); // expect: C
  number(A().n); // expect: 1
  truth(B().n > 2); // expect: true
  truth(C().n); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
