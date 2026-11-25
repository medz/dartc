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

int Function(int) f = same;
num Function(num) g = same<num>;

class S {
  static T st<T>(T t) => t;
}

R app<R>(R Function(int) h) => h(4);
const int Function(int) c = same;
Box<int> Function(int) mk = Box.new;
final mk2 = Box<num>.new;
Pair<A, B> Function(A, B) pr = Pair.new;
void main() {
  number(f(3)); // expect: 3
  show(g(1.5));
  // expect: double
  // expect: 3
  int Function(int) h = S.st;
  number(h(5)); // expect: 5
  truth(identical(c, f)); // expect: true
  truth(f == same<int>); // expect: true
  truth(g == f); // expect: false
  number(app(same)); // expect: 4
  number(call(same, 6)); // expect: 6
  truth(f is int Function(int)); // expect: true
  truth(f is num Function(num)); // expect: false
  truth(g is num Function(num)); // expect: true
  number(mk(8).value); // expect: 8
  truth(mk(8) is Box<int>); // expect: true
  truth(mk2(8) is Box<int>); // expect: false
  truth(mk2(8) is Box<num>); // expect: true
  number(pr(A(1), B(2)).second.n); // expect: 2
  final q = same<A>;
  number(q(A(9)).n); // expect: 9
}

void number(int n) => print(n);

void truth(bool b) => print(b);
