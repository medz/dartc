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
  int n = 1;
  int Function() get get =>
      () => n;
  void Function(int) set() => (v) {
    n = v;
    this.n += 1;
  };
  int Function() lateTwo() {
    return () => self().n;
  }

  P self() => this;
  int field = 3;
  final int Function(int) f = (x) => x + 1;
  int Function() twice() {
    return () {
      int go() => n * 2 + inc();
      return go();
    };
  }

  int inc() => ++n;
  P Function() me() =>
      () => this;
}

class Q extends P {
  @override
  int inc() => n += 100;
  int Function() sup() =>
      () => super.inc();
  int Function() s2() {
    return () {
      return super.n;
    };
  }
}

void main() {
  final p = P();
  final g = p.get, s = p.set();
  number(g()); // expect: 1
  s(5);
  number(g()); // expect: 6
  number(p.twice()()); // expect: 19
  truth(p.me()() == p); // expect: true
  number(p.f(6)); // expect: 7
  final q = Q();
  number(q.twice()()); // expect: 103
  number(q.sup()()); // expect: 102
  number(q.s2()()); // expect: 102
  number(p.lateTwo()()); // expect: 7
}

void number(int n) => print(n);

void truth(bool b) => print(b);
