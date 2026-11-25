class A {
  static int n = 3;
  static int m = trace(4);
  static final A one = A();
  static A? none;
  int get() => n;
  void set(int v) {
    n = v;
    m = v + 1;
  }

  static int twice() => n * 2;
}

class B {
  static int n = 50;
  int f() => n;
}

void main() {
  number(A.n); // expect: 3
  A.n = 6;
  number(A().get()); // expect: 6
  A().set(8);
  number(A.n); // expect: 8
  number(A.m); // expect: 9
  number(A.twice()); // expect: 16
  A.n += 2;
  number(A.n++); // expect: 10
  number(A.n); // expect: 11
  truth(A.one == A.one); // expect: true
  truth(A.none == null); // expect: true
  A.none ??= A.one;
  truth(A.none == A.one); // expect: true
  number(B.n); // expect: 50
  number(B().f()); // expect: 50
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
