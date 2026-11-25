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

T? orNull<T>(bool b, T t) => b ? t : null;
bool isA<T>(Object? o) => o is T;
T to<T>(Object? o) => o as T;
Pair<X, Y> pair<X, Y>(X x, {required Y y}) => Pair(x, y);
Box<T> box<T>(T t) => Box<T>(t);
int count<T>(Object? a, Object? b) => (a is T ? 1 : 0) + (b is T ? 1 : 0);
T pick<T>(int n, T a, [T? b]) => n > 0 ? a : b ?? a;
void each<T>(T a, T b, void Function(T) f) {
  f(a);
  f(b);
}

bool inner<T>(Object? o) => isA<Box<T>>(o);
bool opt<T>(Object? o) => isA<T?>(o);
void main() {
  number(same(4) + 1); // expect: 5
  truth(same(1.5) > 1); // expect: true
  show(same(null)); // expect: null
  number(same(A(3)).n); // expect: 3
  show(orNull(false, 5)); // expect: null
  show(orNull(true, 5)); // expect: 5
  truth(isA<int>(1)); // expect: true
  truth(isA<int>(1.5)); // expect: false
  truth(isA<int?>(null)); // expect: true
  truth(isA<A>(B(1))); // expect: true
  truth(isA<Box<num>>(Box(1))); // expect: true
  number(to<int>(6) + 1); // expect: 7
  try {
    to<A>(1);
  } on TypeError {
    print('T');
  }
  // expect: T
  number(pair(1, y: A(2)).second.n); // expect: 2
  truth(box(1) is Box<int>); // expect: true
  truth(box<num>(1) is Box<int>); // expect: false
  number(count<num>(1, A(1))); // expect: 1
  number(count<Object>(1, null)); // expect: 1
  number(pick(0, 1, 2)); // expect: 2
  number(pick(0, 7)); // expect: 7
  each(1, 2, number);
  // expect: 1
  // expect: 2
  each<num>(1, 2.5, show);
  // expect: 1
  // expect: double
  // expect: 5
  truth(inner<int>(Box(1))); // expect: true
  truth(inner<double>(Box(1))); // expect: false
  truth(opt<int>(null)); // expect: true
  truth(opt<int>(1.5)); // expect: false
  number(call(twice, 5)); // expect: 10
  number(call((A a) => a.n, A(6))); // expect: 6
  truth(call<int, num>(twice, 4) is int); // expect: true
  final s = same<int>(9);
  number(s); // expect: 9
}

void number(int n) => print(n);

void truth(bool b) => print(b);
