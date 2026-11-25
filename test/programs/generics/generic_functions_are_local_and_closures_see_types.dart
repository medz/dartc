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

Object? make<T>(T t) {
  Box<T> b() => Box<T>(t);
  S id<S>(S s) => s;
  bool both<S>(Object? o) => o is Pair<T, S>;
  final f = (Object? o) => o is T;
  truth(f(1));
  truth(f(1.5));
  truth(both<int>(Pair<T, int>(t, 1)));
  show(id(t));
  return () => b();
}

class G<T> {
  bool Function(Object?) tester() =>
      (o) => o is T;
  Box<S> Function(S) maker<S>() =>
      (s) => Box<S>(s);
  T Function(T) idf() {
    T go(T t) => t;
    return go;
  }
}

void main() {
  final f = make(1);
  // expect: true
  // expect: false
  // expect: true
  // expect: 1
  truth(f is Object? Function()); // expect: true
  truth(f is Box<int> Function()); // expect: true
  truth(f is Box<double> Function()); // expect: false
  final g = make<num>(1);
  // expect: true
  // expect: true
  // expect: true
  // expect: 1
  truth(g is Box<int> Function()); // expect: false
  truth((g as Box<num> Function())() is Box<num>); // expect: true
  truth(G<int>().tester()(1)); // expect: true
  truth(G<int>().tester()(1.5)); // expect: false
  truth(G<int>().maker<A>()(A(1)) is Box<A>); // expect: true
  truth(G<int>().idf() is int Function(int)); // expect: true
  truth(G<int>().idf() is num Function(int)); // expect: true
  truth(G<int>().idf() is int Function(Object)); // expect: false
  number(G<int>().idf()(7)); // expect: 7
}

void number(int n) => print(n);

void truth(bool b) => print(b);
