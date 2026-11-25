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

const p = Pair(1, A(2));
const q = Pair<num, A>(1, B(2));
const Node<int> n = Node(1, Node(2));
Object? def([Object? o = const Box2<int>(5)]) => o;

class Box2<T> {
  final T t;
  const Box2(this.t);
  bool holds(Object? o) => o is T;
}

void main() {
  number(p.first); // expect: 1
  number(p.second.n); // expect: 2
  truth(identical(p, const Pair(1, A(2)))); // expect: true
  truth(identical(const Pair<num, A>(1, A(2)), p)); // expect: false
  truth(const Pair(1, A(2)) is Pair<int, A>); // expect: true
  truth(q is Pair<int, A>); // expect: false
  n.each(number);
  // expect: 1
  // expect: 2
  truth(def() is Box2<int>); // expect: true
  truth(const Box2<int>(1).holds(2)); // expect: true
  truth(const Box2<num>(1).holds(2.5)); // expect: true
  truth(const Box2(1).holds(2.5)); // expect: false
  truth(identical(const Box2<int>(1), const Box2<num>(1))); // expect: false
}

void number(int n) => print(n);

void truth(bool b) => print(b);
