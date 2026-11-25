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

class P {
  int n;
  P? next;
  List1? list;
  void Function(int)? f;
  dynamic d;
  P(this.n, [this.next]);
  int get twice => n * 2;
  P add(int k) {
    n += k;
    return this;
  }

  P? maybe(bool b) => b ? this : null;
  int operator [](int i) => n + i;
  void operator []=(int i, int v) {
    n = i * 10 + v;
  }

  set s(int v) {
    number(v);
  }

  void call() {
    print('call');
  }

  P operator +(int k) => P(n + k);
  int? get none => null;
}

class List1 {
  int? x;
  P? p = P(50);
  int len = 0;
  void add(int v) {
    len++;
    x = v;
  }

  List1? self() => this;
  int operator [](int i) => len + i;
  void operator []=(int i, int v) {
    len = v;
  }
}

P? pick(int n) {
  print('pick');
  switch (n) {
    case 0:
      return null;
    case 1:
      return P(1);
  }
  final p = P(2, P(3, P(4)));
  p.list = List1();
  p.next?.list = List1();
  return p;
}

class A {
  final int n;
  A(this.n);
  factory A.b(int n, [int k]) = B;
  factory A.c({required int z}) = C.named;
  factory A.g() = G<int>;
  const factory A.k(int n) = K;
  factory A.two(int n) = A.b;
}

class B extends A {
  B(super.n, [int k = 5]) {
    number(k);
  }
}

class C extends A {
  C.named({required int z, int y = 2}) : super(z * y);
}

class G<T> extends A {
  G() : super(7);
  bool has(Object? o) => o is T;
}

class K implements A {
  @override
  final int n;
  const K(this.n);
}

class L<T> {
  L();
  factory L.sub(T t) = M<T>;
  factory L.pair(T a) = N<T, bool>;
  factory L.fix() = M<T>.fixed;
  T? get first => null;
}

class M<T> extends L<T> {
  final T? t;
  M(this.t);
  M.fixed() : t = null;
  @override
  T? get first => t;
}

class N<X, Y> extends L<X> {
  final X x;
  N(this.x);
  bool isY(Object? o) => o is Y;
}

void main() {
  number(A.b(1).n);
  // expect: 5
  // expect: 1
  number(A.b(1, 2).n);
  // expect: 2
  // expect: 1
  number(A.c(z: 4).n); // expect: 8
  final g = A.g();
  truth(g is G<int>); // expect: true
  number(const A.k(3).n); // expect: 3
  truth(identical(const A.k(3), const K(3))); // expect: true
  number(A.two(6).n);
  // expect: 5
  // expect: 6
  L<int> l = L.sub(4);
  show(l.first); // expect: 4
  truth(l is M<int>); // expect: true
  final p = L<num>.pair(1.5);
  truth(p is N<num, bool>); // expect: true
  truth(p is N<int, bool>); // expect: false
  truth(L<int>.fix() is M<int>); // expect: true
  final f = A.b;
  number(f(9).n);
  // expect: 5
  // expect: 9
  L<int> Function(int) h = L.sub;
  truth(h(1) is M<int>); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
