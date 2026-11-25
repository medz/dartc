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
  } else if (o is A) {
    print('A');
    number(o.n);
  } else {
    print('other');
  }
}

class A {
  final int n;
  const A(this.n);
}

class B extends A {
  const B(super.n);
}

class Box<T> {
  T value;
  Box(this.value);
  T get() => value;
  void set(T v) {
    value = v;
  }

  Box<T> copy() => Box(value);
  Box<S> map<S>(S Function(T) f) => Box(f(value));
  bool holds(Object? o) => o is T;
  T cast(Object? o) => o as T;
}

class Pair<X, Y> {
  final X first;
  final Y second;
  const Pair(this.first, this.second);
  Pair<Y, X> swap() => Pair(second, first);
}

class Node<T> {
  final T item;
  final Node<T>? next;
  const Node(this.item, [this.next]);
  void each(void Function(T) f) {
    Node<T>? at = this;
    while (at != null) {
      f(at.item);
      at = at.next;
    }
  }

  R fold<R>(R start, R Function(R, T) f) {
    var r = start;
    each((t) => r = f(r, t));
    return r;
  }
}

T same<T>(T t) => t;
R call<T, R>(R Function(T) f, T t) => f(t);
int twice(int n) => n * 2;

class C<T> {
  final T a;
  T? b;
  final int k;
  static int made = 0;
  static T id<T>(T t) => t;
  C(this.a, {this.b, this.k = 3}) {
    made++;
  }
  C.twice(T t) : this(t, b: t);
  C.init(T t) : a = t, b = null, k = 1;
  factory C.of(T t) => C(t, k: 9);
  Box<T> box() => Box<T>(a);
  List2<T> list() => List2();
}

class D<T> extends C<T> {
  D(T t) : super(t, k: 5);
  D.named(super.a, {super.b, super.k}) : super();
}

class List2<T> {
  bool ok(Object? o) => o is T;
}

void main() {
  number(C(1).a); // expect: 1
  number(C(2, b: 4, k: 7).k); // expect: 7
  show(C(2, b: 4).b); // expect: 4
  show(C.twice(6).b); // expect: 6
  number(C.init(A(3)).a.n); // expect: 3
  number(C.of(5).k); // expect: 9
  number(D(8).k); // expect: 5
  show(D.named(1.5, k: 2).a);
  // expect: double
  // expect: 3
  show(D.named(1, b: 2).b); // expect: 2
  number(C.made); // expect: 8
  number(C.id(11)); // expect: 11
  truth(C.of(5).box().holds(1)); // expect: true
  truth(C.of(5).box().holds(1.5)); // expect: false
  truth(D(A(1)).list().ok(B(2))); // expect: true
  truth(D<B>(B(1)).list().ok(A(2))); // expect: false
  C<num> c = C.of(3);
  truth(c.box().holds(1.5)); // expect: true
}

void number(int n) => print(n);

void truth(bool b) => print(b);
