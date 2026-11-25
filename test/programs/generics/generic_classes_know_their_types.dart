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

void t(Object? o) {
  truth(o is Box);
  truth(o is Box<int>);
  truth(o is Box<num>);
  truth(o is Box<Object>);
  truth(o is Box<int?>);
  truth(o is Box<Box<int>>);
  truth(o is Pair<int, num>);
  truth(o is Box<dynamic>);
  truth(o is Box<A>?);
  truth(o is Sub);
  truth(o is Get<num>);
  truth(o is Get<Get<int>>);
  print('-');
}

abstract class Get<T> {}

class Sub extends Box<int> implements Get<double> {
  Sub() : super(1);
}

class Deep<T> extends Pair<T, Box<T>> implements Get<Get<T>> {
  Deep(T t) : super(t, Box(t));
}

void main() {
  t(Box(1));
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box(1.5));
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<num>(1));
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<int?>(1));
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box(Box(1)));
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<Object?>(1));
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<dynamic>(1));
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Pair(1, 2));
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Pair(1, 2.5));
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Sub());
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: -
  t(Deep(1));
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: -
  t(Deep<num>(1));
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(null);
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<A>(B(1)));
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box<B>(B(1)));
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(Box(null));
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: true
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  t(1);
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: false
  // expect: -
  Object o = Box(5);
  if (o is Box<int>) number(o.value + 1); // expect: 6
  number((o as Box<num>).value.toInt()); // expect: 5
  try {
    o as Box<double>;
  } on TypeError {
    print('T');
  }
  // expect: T
  Object? p = Deep(4);
  if (p is Pair<int, Box<int>>) number(p.second.value); // expect: 4
}

void number(int n) => print(n);

void truth(bool b) => print(b);
