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

class P<T> {
  void put(T t) {
    show(t);
  }

  void f(void Function(T) g) {}
  T id(T t) => t;
  void c(covariant num n) {
    show(n);
  }

  void two([T? a]) {
    show(a);
  }

  void named({required T a, int b = 1}) {
    show(a);
    number(b);
  }
}

class Q extends P<int> {
  @override
  void put(int t) {
    show(t);
  }

  @override
  void named({required int a, int b = 2}) {
    number(a + b);
  }
}

void t(Object o) {
  truth(o is void Function(Object?));
  truth(o is void Function(Null));
  truth(o is void Function(int));
  truth(o is void Function(void Function(int)));
  truth(o is void Function({required num a, int b}));
  print('-');
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
  t(P<int>().put);
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(P<int>().f);
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: -
  t(P<int>().id);
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(P<int>().c);
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(P<int>().two);
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(Q().put);
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(Q().named);
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: -
  P<num> p = P<int>();
  final f = p.put;
  go(() => f(1.5)); // expect: T
  go(() => f(2));
  // expect: 2
  // expect: ok
  final Object g = p.c;
  go(() => (g as void Function(Object?))(true)); // expect: T
  go(() => (g as void Function(Object?))(3));
  // expect: 3
  // expect: ok
  P<num> q = Q();
  go(() => (q.put)(1.5)); // expect: T
  go(() => (q.put)(4));
  // expect: 4
  // expect: ok
  go(() => (q.two)(2.5)); // expect: T
  go(() => (q.two)());
  // expect: null
  // expect: ok
  final n = q.named;
  go(() => n(a: 1.5)); // expect: T
  go(() => n(a: 5, b: 6));
  // expect: 11
  // expect: ok
  go(() => show(p.id(7)));
  // expect: 7
  // expect: ok
  go(() => show((p.id)(8.5))); // expect: T
}

void number(int n) => print(n);

void truth(bool b) => print(b);
