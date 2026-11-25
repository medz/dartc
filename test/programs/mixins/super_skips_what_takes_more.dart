void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is bool) {
    truth(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else {
    print('other');
  }
}

class A {
  int f(int a) => a;
  int g({int x = 1}) => x;
}

mixin M on A {
  @override
  int f(int a, [int b = 2]) => super.f(a) + b;
  @override
  int g({int x = 2, int y = 3}) => super.g(x: x) * y;
}

mixin N on A {
  @override
  int f(int a, [int b = 5, int c = 7]) => super.f(a) + b * c;
}

class B extends A with M, N {}

void main() {
  number(B().f(1)); // expect: 38
  number(B().f(1, 2, 3)); // expect: 9
  number(B().g()); // expect: 6
  number(B().g(y: 5)); // expect: 10
  A a = B();
  number(a.f(4)); // expect: 41
  number(a.g(x: 9)); // expect: 27
}

void number(int n) => print(n);

void truth(bool b) => print(b);
