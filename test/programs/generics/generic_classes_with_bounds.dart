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

abstract class Shape {
  int area();
}

class Sq extends Shape {
  final int s;
  Sq(this.s);
  @override
  int area() => s * s;
}

class Max<T extends num> {
  T a;
  Max(this.a);
  num plus(T b) => a + b;
  bool less(T b) => a < b;
  T get() => a;
  double half() => a / 2;
  int whole() => a.toInt();
}

class Holder<T extends Shape> {
  final T t;
  Holder(this.t);
  int twice() => t.area() * 2;
  bool eq(T o) => t == o;
}

int area<T extends Shape>(T t) => t.area();
T biggest<T extends Shape>(T a, T b) => a.area() > b.area() ? a : b;
T next<T extends Object>(T? t, T d) => t ?? d;
bool flag<T extends bool>(T t) => t ? true : false;
num sum<T extends num>(T a, T b) {
  num r = a;
  r += b;
  return r;
}

void main() {
  final m = Max(3);
  show(m.plus(4)); // expect: 7
  truth(m.less(9)); // expect: true
  number(m.get() + 1); // expect: 4
  truth(m.half() == 1.5); // expect: true
  number(Max(2.5).whole()); // expect: 2
  show(Max<num>(1).plus(0.5));
  // expect: double
  // expect: 3
  number(Holder(Sq(3)).twice()); // expect: 18
  final s = Sq(2);
  truth(Holder(s).eq(s)); // expect: true
  number(area(Sq(5))); // expect: 25
  number(biggest(Sq(1), Sq(6)).s); // expect: 6
  number(next(null, 4)); // expect: 4
  number(next(5, 4)); // expect: 5
  truth(flag(true)); // expect: true
  show(sum(1, 2)); // expect: 3
  show(sum(1.5, 2.5));
  // expect: double
  // expect: 8
}

void number(int n) => print(n);

void truth(bool b) => print(b);
