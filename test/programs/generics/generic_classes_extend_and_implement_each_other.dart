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

abstract class Get<T> {
  T get();
  int size() => 1;
}

abstract class Put<T> {
  void put(T t);
}

class Cell<T> implements Get<T>, Put<T> {
  T t;
  Cell(this.t);
  @override
  T get() => t;
  @override
  void put(T x) {
    t = x;
  }

  @override
  int size() => 2;
}

class IntCell extends Cell<int> {
  IntCell(super.t);
  @override
  int get() => super.get() + 1;
  int twice() => t * 2;
}

class Same<T> extends Cell<Pair<T, T>> {
  Same(T a) : super(Pair(a, a));
  T left() => t.first;
}

class Opt<T> extends Get<T?> {
  @override
  T? get() => null;
}

T take<T>(Get<T> g) => g.get();
void main() {
  final c = Cell(3);
  c.put(4);
  number(c.get()); // expect: 4
  number(take(c)); // expect: 4
  Get<int> g = IntCell(5);
  number(g.get()); // expect: 6
  number(g.size()); // expect: 2
  number(IntCell(6).twice()); // expect: 12
  Cell<int> k = IntCell(7);
  k.t = 9;
  number(k.get()); // expect: 10
  k.put(1);
  number(k.t); // expect: 1
  final s = Same(A(8));
  number(s.left().n); // expect: 8
  number(s.get().second.n); // expect: 8
  show(Opt<int>().get()); // expect: null
  number(Opt<A>().size()); // expect: 1
  Put<int> p = c;
  p.put(20);
  number(c.t); // expect: 20
  num z = take<num>(c);
  show(z); // expect: 20
}

void number(int n) => print(n);

void truth(bool b) => print(b);
