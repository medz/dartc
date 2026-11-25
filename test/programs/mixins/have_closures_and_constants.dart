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

mixin M {
  int x = 1;
  int Function() f() =>
      () => x++;
  int Function() get t => g;
  int g() => x * 10;
}

class A with M {}

class B with M {
  B() {
    x = 5;
  }
  @override
  int g() => super.g() + 1;
  int Function() sup() => super.g;
}

mixin K {
  int get k => 7;
}

class C with K {
  final int n;
  const C(this.n);
}

class CC extends C {
  const CC() : super(4);
  @override
  int get k => super.k * n;
}

void main() {
  final a = A(), b = B();
  final f = a.f();
  number(f()); // expect: 1
  number(f()); // expect: 2
  number(a.x); // expect: 3
  number(b.t()); // expect: 51
  number(b.sup()()); // expect: 50
  number(b.f()()); // expect: 5
  number(const C(3).k); // expect: 7
  number(const CC().k); // expect: 28
  truth(identical(const CC(), const CC())); // expect: true
  truth(const C(1) is K); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
