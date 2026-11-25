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

class S {
  int f(int n) {
    print('S');
    return n;
  }

  int get g => 1;
  set g(int v) {
    print('set');
    number(v);
  }

  int operator +(int o) => o;
  int h = 4;
}

mixin A on S {
  @override
  int f(int n, [int z = 0]) {
    print('A');
    return super.f(n + 1) * 10;
  }

  @override
  int get g => super.g + 10;
  @override
  set g(int v) {
    super.g = v + 1;
  }

  @override
  int operator +(int o) => super + (o + 5);
  @override
  int get h => super.h * 2;
  @override
  set h(int v) {
    super.h = v + 1;
  }
}

mixin B on S {
  @override
  int f(int n, [int k = 7]) {
    print('B');
    return super.f(n + k) + 1;
  }

  @override
  int get g => super.g + 100;
}

class X extends S with A, B {}

class Y extends S with B, A {}

class Z extends X with A {
  @override
  int f(int n, [int k = 1]) {
    print('Z');
    return super.f(n, k);
  }
}

class W = S with A;
void t(S s) {
  number(s.f(1));
  number(s.g);
  s.g = 5;
  number(s + 2);
  number(s.h);
  s.h = 20;
  number(s.h);
}

void main() {
  t(S());
  // expect: S
  // expect: 1
  // expect: 1
  // expect: set
  // expect: 5
  // expect: 2
  // expect: 4
  // expect: 20
  t(X());
  // expect: B
  // expect: A
  // expect: S
  // expect: 91
  // expect: 111
  // expect: set
  // expect: 6
  // expect: 7
  // expect: 8
  // expect: 42
  t(Y());
  // expect: A
  // expect: B
  // expect: S
  // expect: 100
  // expect: 111
  // expect: set
  // expect: 6
  // expect: 7
  // expect: 8
  // expect: 42
  t(Z());
  // expect: Z
  // expect: A
  // expect: B
  // expect: A
  // expect: S
  // expect: 1010
  // expect: 121
  // expect: set
  // expect: 7
  // expect: 12
  // expect: 16
  // expect: 88
  t(W());
  // expect: A
  // expect: S
  // expect: 20
  // expect: 11
  // expect: set
  // expect: 6
  // expect: 7
  // expect: 8
  // expect: 42
  number(X().f(1, 2));
  // expect: B
  // expect: A
  // expect: S
  // expect: 41
  int Function(int) q = Y().f;
  number(q(3));
  // expect: A
  // expect: B
  // expect: S
  // expect: 120
  truth(X().f == X().f); // expect: false
  final x = X();
  truth(x.f == x.f); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
