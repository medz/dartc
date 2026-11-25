class A {
  final int n;
  A(this.n);
}

class B extends A {
  B(super.n);
}

abstract class I {}

class C implements I {
  const C();
}

int zero() => 0;
bool yes() => zero() == 0;

/// Says what any object is.
void show(Object? o) {
  if (o == null) {
    print('null');
  } else if (o is int) {
    number(o);
  } else if (o is double) {
    print('double');
    number((o * 2).toInt());
  } else if (o is bool) {
    truth(o);
  } else if (o is B) {
    print('B');
    number(o.n);
  } else if (o is A) {
    print('A');
    number(o.n);
  } else {
    print('other');
  }
}

Object? pick(int n) {
  switch (n) {
    case 0:
      return 7;
    case 1:
      return 2.5;
    case 2:
      return true;
    case 3:
      return A(3);
    case 4:
      return B(4);
    case 5:
      return null;
    case 6:
      return C();
    case 7:
      return -0.0;
    case 8:
      return false;
    case 9:
      return 0 / 0;
  }
  return 1 << 62;
}

void t(int n) {
  try {
    final o = pick(n);
    if (o != null) throw o;
  } on int catch (e) {
    number(e + 1);
  } on num catch (e) {
    show(e + 1);
  } on bool catch (e) {
    truth(e);
  } on A catch (e) {
    number(e.n);
  } catch (e) {
    show(e);
  }
}

void main() {
  for (var i = 0; i < 9; i++) t(i);
  // expect: 8
  // expect: double
  // expect: 7
  // expect: true
  // expect: 3
  // expect: 4
  // expect: other
  // expect: double
  // expect: 2
  // expect: false
  try {
    throw 5;
  } on double {
    print('no');
  } catch (e) {
    show(e);
  }
  // expect: 5
  throw -42;
}

void number(int n) => print(n);

void truth(bool b) => print(b);
// stderr: Unhandled exception:
// stderr: -42
// exit: 255
