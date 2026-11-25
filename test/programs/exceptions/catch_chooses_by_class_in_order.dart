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

void t(int n) {
  try {
    any(n);
    print('none');
  } on B catch (e) {
    print('B');
    number(e.n);
  } on I {
    print('I');
  } on A catch (e) {
    print('A');
    number(e.n);
  } on Exception {
    print('Exception');
  } on Error catch (e) {
    print('Error');
  }
}

void main() {
  for (var i = 0; i < 7; i++) t(i);
  // expect: none
  // expect: A
  // expect: 1
  // expect: B
  // expect: 2
  // expect: Exception
  // expect: Error
  // expect: I
  // expect: Exception
}

void number(int n) => print(n);
