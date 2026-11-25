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

num add<T>(T t) {
  if (t is int) return t + 1;
  if (t is num) return t * 2;
  return -1;
}

T inc<T extends num>(T t) {
  if (t is int) {
    final int k = t;
    number(k + 1);
  }
  return t;
}

int len<T>(T? t) {
  if (t == null) return 0;
  if (t is A) return t.n;
  return 1;
}

void main() {
  show(add(1)); // expect: 2
  show(add(1.5));
  // expect: double
  // expect: 6
  show(add(A(1))); // expect: -1
  number(inc(4));
  // expect: 5
  // expect: 4
  show(inc(1.5));
  // expect: double
  // expect: 3
  number(len<A>(null)); // expect: 0
  number(len(B(6))); // expect: 6
  number(len(1)); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);
