abstract class I {
  int f(int x);
  int get p;
  set p(int v);
}

abstract class Half implements I {
  @override
  int get p => 40;
  int both() => f(1) + p;
}

class J implements I {
  @override
  int p = 3;
  @override
  int f(int x, [int y = 10]) => x + y + p;
}

class K extends J {
  @override
  int f(int x, [int y = 20]) => super.f(x, y) * 2;
  @override
  int get p => super.p + 100;
}

class L extends Half {
  int stored = 0;
  @override
  int f(int x) => -x;
  @override
  set p(int v) {
    stored = v * 2;
  }
}

void use(I i) {
  i.p = 5;
  number(i.f(1));
  number(i.p);
  i.p += 1;
  number(i.p);
}

void main() {
  use(J());
  // expect: 16
  // expect: 5
  // expect: 6
  use(K());
  // expect: 252
  // expect: 105
  // expect: 206
  final l = L();
  use(l);
  // expect: -1
  // expect: 40
  // expect: 40
  number(l.stored); // expect: 82
  number(l.both()); // expect: 39
}

void number(int n) => print(n);
