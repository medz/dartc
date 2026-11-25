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
  }
  // expect: 14
  // expect: 0
  // expect: 49
  // expect: double
  // expect: 2
  // expect: 1
  // expect: 0
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: 14
  // expect: 13
  // expect: 26
  // expect: 27
  // expect: 26
  // expect: double
  // expect: 19
  // expect: double
  // expect: 9
  // expect: double
  // expect: 35
  // expect: double
  // expect: 5
  // expect: 2
  // expect: double
  // expect: 4
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: double
  // expect: 19
  // expect: double
  // expect: 17
  // expect: double
  // expect: 34
  // expect: double
  // expect: 36
  // expect: double
  // expect: 34
  // expect: 4
  // expect: 10
  // expect: -21
  // expect: double
  // expect: -4
  // expect: -2
  // expect: 1
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: 4
  // expect: 3
  // expect: 6
  // expect: 7
  // expect: 6
  // expect: double
  // expect: 13
  // expect: double
  // expect: 15
  // expect: double
  // expect: -7
  // expect: double
  // expect: -28
  // expect: -14
  // expect: double
  // expect: 0
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: double
  // expect: 13
  // expect: double
  // expect: 11
  // expect: double
  // expect: 22
  // expect: double
  // expect: 24
  // expect: double
  // expect: 22
  // expect: -7
  // expect: 8
  // expect: 8
  // expect: double
  // expect: 17
  // expect: double
  // expect: 7
  // expect: -4
  // expect: 1
  // expect: 7
  // expect: double
  // expect: 14
  // expect: 12
  // expect: double
  // expect: 17
  // expect: double
  // expect: 119
  // expect: double
  // expect: 1
  // expect: 0
  // expect: 5
  // expect: false
  // expect: false
  // expect: false
  // expect: double
  // expect: 19
  // expect: double
  // expect: -9
  // expect: double
  // expect: 35
  // expect: double
  // expect: 0
  // expect: 0
  // expect: double
  // expect: 5
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: double
  // expect: 19
  // expect: double
  // expect: 17
  // expect: double
  // expect: 34
  // expect: double
  // expect: 36
  // expect: double
  // expect: 34
  // expect: double
  // expect: 10
  // expect: double
  // expect: 0
  // expect: double
  // expect: 12
  // expect: double
  // expect: 2
  // expect: 1
  // expect: double
  // expect: 0
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: double
  // expect: 10
  // expect: double
  // expect: 8
  // expect: double
  // expect: 16
  // expect: double
  // expect: 18
  // expect: double
  // expect: 16
  // expect: double
  // expect: -1
  // expect: double
  // expect: 11
  // expect: double
  // expect: -15
  // expect: double
  // expect: -1
  // expect: 0
  // expect: double
  // expect: 5
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: double
  // expect: -1
  // expect: double
  // expect: -3
  // expect: double
  // expect: -6
  // expect: double
  // expect: -4
  // expect: double
  // expect: -6
  // expect: double
  // expect: 4
  // expect: double
  // expect: 6
  // expect: double
  // expect: -2
  // expect: double
  // expect: -10
  // expect: -5
  // expect: double
  // expect: 0
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: double
  // expect: 4
  // expect: double
  // expect: 2
  // expect: double
  // expect: 4
  // expect: double
  // expect: 6
  // expect: double
  // expect: 4
  // expect: double
  // expect: -5
  // expect: double
  // expect: 7
  // expect: double
  // expect: 7
  // expect: double
  // expect: 8
  // expect: double
  // expect: 2
  // expect: double
  // expect: 1
  // expect: 1
  // expect: 2
  // expect: double
  // expect: 5
  // expect: double
  // expect: 15
  // expect: double
  // expect: 8
  // expect: double
  // expect: 20
  // expect: double
  // expect: 4
  // expect: 2
  // expect: double
  // expect: 0
  // expect: true
  // expect: false
  // expect: false
  // expect: 4
  // expect: -10
  // expect: -21
  // expect: double
  // expect: 0
  // expect: 0
  // expect: 4
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: 4
  // expect: 3
  // expect: 6
  // expect: 7
  // expect: 6
  // expect: double
  // expect: -1
  // expect: double
  // expect: -11
  // expect: double
  // expect: -15
  // expect: double
  // expect: -2
  // expect: -1
  // expect: double
  // expect: 4
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: double
  // expect: -1
  // expect: double
  // expect: -3
  // expect: double
  // expect: -6
  // expect: double
  // expect: -4
  // expect: double
  // expect: -6
  // expect: -6
  // expect: 0
  // expect: 9
  // expect: double
  // expect: 2
  // expect: 1
  // expect: 0
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: -6
  // expect: -7
  // expect: -14
  // expect: -13
  // expect: -14
  // expect: double
  // expect: -7
  // expect: double
  // expect: -5
  // expect: double
  // expect: 3
  // expect: double
  // expect: 12
  // expect: 6
  // expect: double
  // expect: 0
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: double
  // expect: -7
  // expect: double
  // expect: -9
  // expect: double
  // expect: -18
  // expect: double
  // expect: -16
  // expect: double
  // expect: -18
  // expect: 3
  // expect: -2
  // expect: -2
  // expect: double
  // expect: -3
  // expect: double
  // expect: -3
  // expect: 6
  // expect: 2
  // expect: -3
  // expect: double
  // expect: -6
  // expect: 2
  // expect: double
  // expect: -3
  // expect: double
  // expect: 9
  // expect: double
  // expect: -3
  // expect: -1
  // expect: 2
  // expect: true
  // expect: false
  // expect: false
  // expect: double
  // expect: 13
  // expect: double
  // expect: -15
  // expect: double
  // expect: -7
  // expect: double
  // expect: 0
  // expect: 0
  // expect: double
  // expect: 13
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: double
  // expect: 13
  // expect: double
  // expect: 11
  // expect: double
  // expect: 22
  // expect: double
  // expect: 24
  // expect: double
  // expect: 22
  // expect: double
  // expect: 4
  // expect: double
  // expect: -6
  // expect: double
  // expect: -2
  // expect: double
  // expect: 0
  // expect: 0
  // expect: double
  // expect: 4
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: double
  // expect: 4
  // expect: double
  // expect: 2
  // expect: double
  // expect: 4
  // expect: double
  // expect: 6
  // expect: double
  // expect: 4
  // expect: double
  // expect: -7
  // expect: double
  // expect: 5
  // expect: double
  // expect: 3
  // expect: double
  // expect: 0
  // expect: 0
  // expect: double
  // expect: 5
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: true
  // expect: double
  // expect: -7
  // expect: double
  // expect: -9
  // expect: double
  // expect: -18
  // expect: double
  // expect: -16
  // expect: double
  // expect: -18
  // expect: double
  // expect: -2
  // expect: double
  // expect: 0
  // expect: double
  // expect: 0
  // expect: double
  // expect: 2
  // expect: 1
  // expect: double
  // expect: 0
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: double
  // expect: -2
  // expect: double
  // expect: -4
  // expect: double
  // expect: -8
  // expect: double
  // expect: -6
  // expect: double
  // expect: -8
  // expect: double
  // expect: 1
  // expect: double
  // expect: 1
  // expect: double
  // expect: 1
  // expect: double
  // expect: 2
  // expect: double
  // expect: 0
  // expect: double
  // expect: 7
  // expect: 2
  // expect: 0
  // expect: double
  // expect: -1
  // expect: double
  // expect: 9
  // expect: double
  // expect: 2
  // expect: double
  // expect: -1
  // expect: double
  // expect: -20
  // expect: -10
  // expect: double
  // expect: 0
  // expect: true
  // expect: true
  // expect: false
  num x = 1;
  x = x is int ? x + 1 : x;
  show(x); // expect: 2
  if (x is int) number(x << 2); // expect: 8
  num sum = 0;
  for (var i = 0; i < 5; i++) {
    sum += i % 2 == 0 ? i : i / 2;
  }
  show(sum);
  // expect: double
  // expect: 16
}

void number(int n) => print(n);

void truth(bool b) => print(b);
