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

int twice(int n) => n * 2;
int apply(int Function(int) f, int n) => f(n);
void run(void Function() f) => f();

class A {
  final int n;
  const A(this.n);
  int add(int m) => n + m;
  void shout() => number(n);
  int get g => n;
}

class B extends A {
  const B(super.n);
  @override
  int add(int m, [int k = 100]) => n + m + k;
}

class P {
  void f(int Function(B) g) => number(g(B(1)));
  num Function(int) h() => twice;
  A Function()? k;
}

class Q extends P {
  @override
  void f(Object? g) {
    print('Q');
  }

  @override
  int Function(num) h() =>
      (n) => n.toInt() + 1;
  @override
  covariant B Function()? k;
}

void use(P p) {
  p.f((b) => b.n);
  show(p.h()(4));
  p.k = () => B(7);
  number(p.k!().n);
  try {
    p.k = () => A(8);
    number(p.k!().n);
  } on TypeError {
    print('T');
  }
}

void main() {
  use(P());
  // expect: 1
  // expect: 8
  // expect: 7
  // expect: 8
  use(Q());
  // expect: Q
  // expect: 5
  // expect: 7
  // expect: T
}

void number(int n) => print(n);

void truth(bool b) => print(b);
