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
  int x = 3;
  int get twice => x * 2;
  void inc([int by = 1]) {
    x += by;
  }

  int abs1();
  int use() => abs1() + twice;
  static int s = 5;
  static int st() => s++;
}

mixin N {
  int y = 10;
  int both() => y + 1;
}

class A with M {
  @override
  int abs1() => 100;
}

class B extends A with N {
  @override
  int both() => super.both() + x;
}

class C with M, N {
  @override
  int abs1() => y;
}

abstract class I {
  int both();
}

class D = A with N implements I;
void main() {
  final a = A();
  a.inc();
  number(a.x); // expect: 4
  number(a.twice); // expect: 8
  a.inc(5);
  number(a.use()); // expect: 118
  final b = B();
  number(b.both()); // expect: 14
  b.x = 7;
  b.y = 20;
  number(b.both()); // expect: 28
  number(b.use()); // expect: 114
  final c = C();
  c.inc(2);
  number(c.use()); // expect: 20
  number(c.both()); // expect: 11
  I d = D();
  number(d.both()); // expect: 11
  truth(a is M); // expect: true
  truth(b is N); // expect: true
  truth(c is M); // expect: true
  truth(d is A); // expect: true
  truth(d is N); // expect: true
  Object o = a;
  truth(o is N); // expect: false
  M m = c;
  number(m.use()); // expect: 20
  M.st();
  number(M.s); // expect: 6
}

void number(int n) => print(n);

void truth(bool b) => print(b);
