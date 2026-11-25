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

class Z {
  int get k => 1;
}

mixin M on Z {
  late int a;
  late final b = k * 10;
  int c() {
    int f(int n) => n < 1 ? super.k : f(n - 1) + k;
    int g() {
      int h() => f(3) + b;
      return h();
    }

    return g();
  }

  int d() {
    late int x = super.k + k;
    void up() {
      x += 1;
    }

    up();
    return x;
  }

  T e<T>(T t) {
    T id(T u) => u;
    return id(t);
  }
}

mixin N on Z {
  @override
  int get k => super.k + 5;
}

class A extends Z with M {}

class B extends Z with N, M {
  @override
  int get k => 100;
}

class C = Z with N, M;

class D extends A with M {}

void main() {
  void use(M o) {
    number(o.b);
    number(o.c());
    number(o.d());
    number(o.e(o.b));
    o.a = 4;
    number(o.a);
  }

  use(A());
  // expect: 10
  // expect: 14
  // expect: 3
  // expect: 10
  // expect: 4
  use(B());
  // expect: 1000
  // expect: 1306
  // expect: 107
  // expect: 1000
  // expect: 4
  use(C());
  // expect: 60
  // expect: 84
  // expect: 13
  // expect: 60
  // expect: 4
  use(D());
  // expect: 10
  // expect: 14
  // expect: 3
  // expect: 10
  // expect: 4
}

void number(int n) => print(n);

void truth(bool b) => print(b);
