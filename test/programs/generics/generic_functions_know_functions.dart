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

bool one<T>() => 1 is T;
bool yes() => one<int>();
void named({int? a}) {}
void other({int? b}) {}

class L<T> {
  List2<T> all() => List2<T>();
}

class List2<T> extends Pair<T?, T Function(int)> {
  List2() : super(null, (t) => throw t);
}

void main() {
  truth(one<int>()); // expect: true
  truth(one<num>()); // expect: true
  truth(one<double>()); // expect: false
  Object a = yes(), b = yes();
  truth(identical(a, b)); // expect: true
  truth(a == b); // expect: true
  Object o = Box<void Function()>(() {});
  truth(o is Box<Function>); // expect: true
  truth(o is Box<int Function()>); // expect: false
  truth(o is Box<void Function([int])>); // expect: false
  Object n = named;
  truth(n is void Function({int a})); // expect: true
  truth(n is void Function({int b})); // expect: false
  truth(n is void Function()); // expect: true
  n = other;
  truth(n is void Function({int b})); // expect: true
  Object p = L<int>().all();
  truth(p is Pair<num?, num Function(int)>); // expect: true
  truth(p is Pair<int?, int Function(int)>); // expect: true
  truth(p is Pair<int, int Function(int)>); // expect: false
}

void number(int n) => print(n);

void truth(bool b) => print(b);
