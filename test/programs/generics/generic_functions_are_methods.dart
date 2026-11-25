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

class M<T> {
  final T t;
  M(this.t);
  R conv<R>(R Function(T) f) => f(t);
  Pair<T, S> with2<S>(S s) => Pair(t, s);
  bool test<S>(Object? o) => o is Pair<T, S>;
  S plain<S>(S s) => s;
  static S st<S>(S s) => s;
}

class N extends M<int> {
  N() : super(4);
  @override
  R conv<R>(R Function(int) f) => f(t + 100);
  @override
  S plain<S>(S s) {
    print('N');
    return super.plain<S>(s);
  }
}

void main() {
  final m = M(3);
  number(m.conv((n) => n * 2)); // expect: 6
  truth(m.conv((n) => n > 2)); // expect: true
  number(m.with2(A(5)).second.n); // expect: 5
  truth(m.with2(1.5) is Pair<int, double>); // expect: true
  truth(m.test<int>(Pair(1, 2))); // expect: true
  truth(m.test<int>(Pair(1, 2.5))); // expect: false
  M<int> n = N();
  number(n.conv((k) => k)); // expect: 104
  number(n.plain(8));
  // expect: N
  // expect: 8
  number(M.st(9)); // expect: 9
  number(n.plain<int>(1));
  // expect: N
  // expect: 1
  M<num> w = n;
  show(w.conv<Object>((k) => k + 0.5));
  // expect: double
  // expect: 209
}

void number(int n) => print(n);

void truth(bool b) => print(b);
