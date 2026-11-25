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

class F<T> {
  void Function(T) f;
  F(this.f);
  void Function(T) get g => f;
  void Function(T) m() => f;
  T Function() r(T t) =>
      () => t;
}

void go(void Function() f) {
  try {
    f();
    print('ok');
  } on TypeError {
    print('T');
  }
}

void main() {
  F<num> f = F<int>((n) => number(n));
  go(() => f.f(1)); // expect: T
  go(() => f.f); // expect: T
  go(() {
    final g = f.g;
    g(1);
  }); // expect: T
  go(() => f.m()(2)); // expect: T
  go(() => show(f.r(3)()));
  // expect: 3
  // expect: ok
  F<int> k = F<int>((n) => number(n));
  go(() => k.f(5));
  // expect: 5
  // expect: ok
  go(() => k.g(6));
  // expect: 6
  // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
