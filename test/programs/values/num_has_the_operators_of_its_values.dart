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
    tell('null');
  } else if (o is int) {
    number(o);
  } else if (o is double) {
    tell('double');
    number((o * 2).toInt());
  } else if (o is bool) {
    truth(o);
  } else if (o is B) {
    tell('B');
    number(o.n);
  } else if (o is A) {
    tell('A');
    number(o.n);
  } else {
    tell('other');
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

num pickNum(int n) => n == 0
    ? 7
    : n == 1
    ? 2.5
    : n == 2
    ? -3
    : -0.5;
void main() {
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      final a = pickNum(i), b = pickNum(j);
      show(a + b);
      show(a - b);
      show(a * b);
      show(a / b);
      show(a ~/ b);
      show(a % b);
      truth(a < b);
      truth(a <= b);
      truth(a > b);
      truth(a >= b);
      truth(a == b);
      truth(a != b);
      var c = a;
      c += b;
      show(c);
      c -= 1;
      show(c);
      c *= 2;
      show(c);
      c++;
      show(c);
      --c;
      show(c);
      endLine();
    }
    final a = pickNum(i);
    show(-a);
    show(a + 1);
    show(1 + a);
    show(1.5 + a);
    show(a * 0.5);
    show(3 - a);
    show(2.0 < a ? 1 : 2);
    show(a.toInt());
    show(a.toDouble());
    int k = 5;
    show(k + a);
    double d = 1.5;
    d += a;
    show(d);
    d = d * a;
    show(d);
    show(k / a);
    show(k ~/ a);
    show(k % a);
    truth(k > a);
    truth(d <= a);
    truth(k == a);
    endLine();
  }
  // expect: 14 0 49 double 2 1 0 false true false true true false 14 13 26 27 26
  // expect: double 19 double 9 double 35 double 5 2 double 4 false false true true false true double 19 double 17 double 34 double 36 double 34
  // expect: 4 10 -21 double -4 -2 1 false false true true false true 4 3 6 7 6
  // expect: double 13 double 15 double -7 double -28 -14 double 0 false false true true false true double 13 double 11 double 22 double 24 double 22
  // expect: -7 8 8 double 17 double 7 -4 1 7 double 14 12 double 17 double 119 double 1 0 5 false false false
  // expect: double 19 double -9 double 35 double 0 0 double 5 true true false false false true double 19 double 17 double 34 double 36 double 34
  // expect: double 10 double 0 double 12 double 2 1 double 0 false true false true true false double 10 double 8 double 16 double 18 double 16
  // expect: double -1 double 11 double -15 double -1 0 double 5 false false true true false true double -1 double -3 double -6 double -4 double -6
  // expect: double 4 double 6 double -2 double -10 -5 double 0 false false true true false true double 4 double 2 double 4 double 6 double 4
  // expect: double -5 double 7 double 7 double 8 double 2 double 1 1 2 double 5 double 15 double 8 double 20 double 4 2 double 0 true false false
  // expect: 4 -10 -21 double 0 0 4 true true false false false true 4 3 6 7 6
  // expect: double -1 double -11 double -15 double -2 -1 double 4 true true false false false true double -1 double -3 double -6 double -4 double -6
  // expect: -6 0 9 double 2 1 0 false true false true true false -6 -7 -14 -13 -14
  // expect: double -7 double -5 double 3 double 12 6 double 0 true true false false false true double -7 double -9 double -18 double -16 double -18
  // expect: 3 -2 -2 double -3 double -3 6 2 -3 double -6 2 double -3 double 9 double -3 -1 2 true false false
  // expect: double 13 double -15 double -7 double 0 0 double 13 true true false false false true double 13 double 11 double 22 double 24 double 22
  // expect: double 4 double -6 double -2 double 0 0 double 4 true true false false false true double 4 double 2 double 4 double 6 double 4
  // expect: double -7 double 5 double 3 double 0 0 double 5 false false true true false true double -7 double -9 double -18 double -16 double -18
  // expect: double -2 double 0 double 0 double 2 1 double 0 false true false true true false double -2 double -4 double -8 double -6 double -8
  // expect: double 1 double 1 double 1 double 2 double 0 double 7 2 0 double -1 double 9 double 2 double -1 double -20 -10 double 0 true true false
  num x = 1;
  x = x is int ? x + 1 : x;
  show(x);
  if (x is int) number(x << 2);
  num sum = 0;
  for (var i = 0; i < 5; i++) {
    sum += i % 2 == 0 ? i : i / 2;
  }
  show(sum);
  endLine(); // expect: 2 8 double 16
}

/// What is told on one line.
final told = <Object?>[];

void tell(Object? o) => told.add(o);

void endLine() {
  print(told.join(' '));
  told.clear();
}

void number(int n) => tell(n);

void truth(bool b) => tell(b);
