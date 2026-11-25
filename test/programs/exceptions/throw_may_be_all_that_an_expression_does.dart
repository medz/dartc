class A {
  final int n;
  A(this.n);
}

class B extends A {
  B(super.n);
}

class C implements Exception {
  const C();
}

class D extends Error {}

abstract class I {}

class J extends A implements I {
  J(super.n);
}

int raise(int n) {
  if (n > 0) throw A(n);
  return n;
}

void any(int n) {
  switch (n) {
    case 1:
      throw A(1);
    case 2:
      throw B(2);
    case 3:
      throw C();
    case 4:
      throw D();
    case 5:
      throw J(5);
    case 6:
      throw const C();
  }
}

int zero() => 0;
A? none() => null;

class N {
  final Never Function(int)? f;
  final N? next;
  N(this.f, this.next);
  Never go(int c) => f?.call(c) ?? next?.go.call(c) ?? last(c);
  Never last(int c) => throw 'last $c';
}

Never stop(int x) => throw 'stop $x';
int pick(Never? Function()? g, bool b) => b ? (g?.call() ?? 3) : 4;
void choose(bool b) {
  try {
    b ? throw 'yes' : throw 'no';
  } catch (e) {
    print('$e');
  }
  try {
    print(b ? stop(1) : throw 'no');
  } catch (e) {
    print('$e');
  }
  try {
    print(switch (b) {
      true => throw 't',
      false => stop(2),
    });
  } catch (e) {
    print('$e');
  }
}

void main() {
  for (final n in [
    N(null, null),
    N(stop, null),
    N(null, N(stop, null)),
    N(null, N(null, null)),
  ]) {
    try {
      n.go(4);
    } catch (e) {
      print('$e');
    }
  }
  // expect: last 4
  // expect: stop 4
  // expect: stop 4
  // expect: last 4
  number(pick(null, true)); // expect: 3
  number(pick(() => null, true)); // expect: 3
  choose(true);
  // expect: yes
  // expect: stop 1
  // expect: t
  choose(false);
  // expect: no
  // expect: no
  // expect: stop 2
}

void number(int n) => print(n);
