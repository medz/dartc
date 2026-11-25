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

class E<T> implements Exception {
  final T t;
  E(this.t);
}

void thrower<T>(T t) => throw E<T>(t);
void tryIt<T>(void Function() f) {
  try {
    f();
  } on E<T> catch (e) {
    print('T');
    show(e.t);
  } on E<num> {
    print('num');
  } on E catch (e) {
    print('E');
    show(e.t);
  }
}

void main() {
  tryIt<int>(() => thrower(1));
  // expect: T
  // expect: 1
  tryIt<int>(() => thrower(1.5)); // expect: num
  tryIt<int>(() => thrower(A(2)));
  // expect: E
  // expect: A
  // expect: 2
  tryIt<Object>(() => thrower(A(2)));
  // expect: T
  // expect: A
  // expect: 2
  tryIt<double>(() => thrower<num>(1.5)); // expect: num
}

void number(int n) => print(n);

void truth(bool b) => print(b);
