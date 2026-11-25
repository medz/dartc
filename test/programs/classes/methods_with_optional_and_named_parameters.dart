class A {
  int f(int a, {int b = 1, int c = 2}) => a * 100 + b * 10 + c;
}

class B extends A {
  @override
  int f(int a, {int c = 7, int b = 8, int d = 9}) =>
      super.f(a, b: b, c: c) + d * 1000;
}

class C implements A {
  @override
  int f(int z, {int b = 5, int c = 6}) => z - b - c;
}

void use(A a) {
  number(a.f(1));
  number(a.f(1, b: 3));
  number(a.f(1, c: 4));
  number(a.f(1, c: 4, b: 3));
  number(a.f(trace(1), c: trace(2), b: trace(3)));
}

void main() {
  use(A());
  // expect: 112
  // expect: 132
  // expect: 114
  // expect: 134
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 132
  use(B());
  // expect: 9187
  // expect: 9137
  // expect: 9184
  // expect: 9134
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: 9132
  use(C());
  // expect: -10
  // expect: -8
  // expect: -8
  // expect: -6
  // expect: 1
  // expect: 2
  // expect: 3
  // expect: -4
  number(B().f(1, d: 2)); // expect: 2187
}

void number(int n) => print(n);

int trace(int n) {
  print(n);
  return n;
}
