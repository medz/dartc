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

int n(int k) {
  number(k);
  return k;
}

class S {
  int a = n(1);
  S(int k) {
    number(k * 100);
  }
  S.named() : a = n(9);
}

mixin M {
  int b = n(2);
  int bb = n(3);
}

mixin N {
  int c = n(4);
  Object? d;
}

class X extends S with M, N {
  int e = n(5);
  X() : super(n(6)) {
    number(a + b + bb + c + e);
  }
  X.two(super.k);
  X.three() : super.named();
}

class Y = S with N, M;

class Z extends Y {
  Z(super.k) {
    show(d);
  }
  Z.n() : super.named();
}

void main() {
  X();
  // expect: 5
  // expect: 6
  // expect: 4
  // expect: 2
  // expect: 3
  // expect: 1
  // expect: 600
  // expect: 15
  X.two(7);
  // expect: 5
  // expect: 4
  // expect: 2
  // expect: 3
  // expect: 1
  // expect: 700
  X.three();
  // expect: 5
  // expect: 4
  // expect: 2
  // expect: 3
  // expect: 1
  // expect: 9
  Y(8);
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 1
  // expect: 800
  Y.named();
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 1
  // expect: 9
  Z(9);
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 1
  // expect: 900
  // expect: null
  Z.n();
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 1
  // expect: 9
  final y = Y(1);
  // expect: 2
  // expect: 3
  // expect: 4
  // expect: 1
  // expect: 100
  y.d = 4;
  show(y.d); // expect: 4
  number(y.b); // expect: 2
}

void number(int n) => print(n);

void truth(bool b) => print(b);
