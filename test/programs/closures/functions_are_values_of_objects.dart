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

class C {
  int n = 1;
  int inc() => ++n;
  void set(int v) {
    n = v;
  }

  C self() => this;
  int Function() both() {
    return inc;
  }

  int call(int a, [int b = 5]) => n * 100 + a * 10 + b;
}

class D extends C {
  @override
  int inc() => n += 10;
  int Function() sup() => super.inc;
  int Function() own() => inc;
  int Function() mine() => this.inc;
}

void main() {
  final c = C();
  final f = c.inc;
  number(f()); // expect: 2
  number(f()); // expect: 3
  number(c.n); // expect: 3
  c.set(50);
  number(f()); // expect: 51
  final s = c.set;
  s(7);
  number(c.n); // expect: 7
  C d = D();
  number(d.inc()); // expect: 11
  number(d.both()()); // expect: 21
  number(D().sup()()); // expect: 2
  number(D().own()()); // expect: 11
  number((d as D).mine()()); // expect: 31
  truth(c.inc == c.inc); // expect: true
  truth(c.inc == f); // expect: true
  truth(c.inc == C().inc); // expect: false
  truth(identical(c.inc, c.inc)); // expect: false
  truth(c.inc == c.self().inc); // expect: true
  truth(d.inc == c.inc); // expect: false
  Object o = c.inc;
  truth(o == f); // expect: true
  truth(f == c.set); // expect: false
  number(c(2)); // expect: 725
  number(c(2, 3)); // expect: 723
  number(c.call(4)); // expect: 745
  int Function(int) g = c;
  number(g(6)); // expect: 765
  number(apply(c, 1)); // expect: 715
  final h = c.call;
  number(h(1, 1)); // expect: 711
  final A a = B(3);
  number(a.add(1)); // expect: 104
  final add = a.add;
  number(add(1)); // expect: 104
  number(apply(a.add, 2)); // expect: 105
  final b = B(4);
  number(b.add(1, 2)); // expect: 7
  int Function(int, int) two = b.add;
  number(two(3, 4)); // expect: 11
  run(a.shout); // expect: 3
  C? n;
  show(n?.inc); // expect: null
  n = c;
  number(n.inc()); // expect: 8
  final Function x = c.inc;
  truth(x == c.inc); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
