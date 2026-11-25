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

mixin class M {
  int x = 2;
  int f() => x;
}

class A extends M {
  @override
  int f() => super.f() + 1;
}

class B with M {
  @override
  int f() => super.f() + 10;
}

abstract class J {
  int j();
}

mixin H on J {
  int hh() => j() * 2;
}

class L implements J {
  @override
  int j() => 6;
}

class R extends L with H {}

void main() {
  number(M().f()); // expect: 2
  number(A().f()); // expect: 3
  number(B().f()); // expect: 12
  number(R().hh()); // expect: 12
  H h = R();
  number(h.hh()); // expect: 12
  number(h.j()); // expect: 6
  try {
    throw B();
  } on M catch (m) {
    number(m.f());
  }
  // expect: 12
}

void number(int n) => print(n);

void truth(bool b) => print(b);
