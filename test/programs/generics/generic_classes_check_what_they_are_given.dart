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

class Put<T> {
  T? t;
  void put(T v) {
    t = v;
  }

  void both(T a, [T? b]) {
    t = b ?? a;
  }

  void named({required T a}) {
    t = a;
  }

  T operator [](T i) => i;
  void operator []=(T i, T v) {
    t = v;
  }

  void all(Box<T> b) {
    t = b.value;
  }

  void fn(void Function(T) f) => f(t as T);
  void fr(T Function() f) {
    t = f();
  }

  set s(T v) {
    t = v;
  }

  bool operator <(T o) => true;
}

class IntPut extends Put<int> {
  @override
  void put(int v) {
    t = v + 1;
  }
}

void go(void Function() f) {
  try {
    f();
    print('ok');
  } on TypeError {
    print('T');
  }
}

void main() {
  Put<num> p = Put<int>();
  go(() => p.put(1)); // expect: ok
  go(() => p.put(1.5)); // expect: T
  go(() => p.both(1, 2.5)); // expect: T
  go(() => p.both(2)); // expect: ok
  go(() => p.named(a: 0.5)); // expect: T
  go(() => p[0.5]); // expect: T
  go(() => p[1] = 1.5); // expect: T
  go(() => p[1] = 2); // expect: ok
  go(() => p.t = 1.5); // expect: T
  go(() => p.t = 3); // expect: ok
  go(() => p.all(Box(1.5))); // expect: T
  go(() => p.all(Box<int>(4))); // expect: ok
  go(() => p.all(Box<num>(4))); // expect: T
  go(() => p.s = 7.5); // expect: T
  go(() => p.s = 7); // expect: ok
  go(() => p < 1.5); // expect: T
  go(() => p < 1); // expect: ok
  go(() => p.fn((n) => show(n)));
  // expect: 7
  // expect: ok
  go(() => p.fr(() => 1.5)); // expect: T
  go(() => p.fr(() => 8)); // expect: ok
  show(p.t); // expect: 8
  Put<num> q = IntPut();
  go(() => q.put(1.5)); // expect: T
  go(() => q.put(5)); // expect: ok
  show(q.t); // expect: 6
  Put<Object?> r = p;
  go(() => r.put(null)); // expect: T
  go(() => r.put(true)); // expect: T
  dynamic d = 1;
  go(() => r.put(d)); // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
