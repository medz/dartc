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

void main() {
  final i = Box(5);
  number(i.value + 1); // expect: 6
  i.value = 7;
  number(i.get()); // expect: 7
  i.set(i.value * 2);
  number(i.copy().value); // expect: 14
  i.value += 3;
  number(i.value++); // expect: 17
  number(i.value); // expect: 18
  final d = Box(1.5),
      b = Box(true),
      a = Box(A(4)),
      n = Box<int?>(null),
      o = Box<Object?>(3),
      m = Box<num>(2);
  truth(d.value > 1); // expect: true
  if (b.value) print('yes'); // expect: yes
  number(a.value.n); // expect: 4
  show(n.value); // expect: null
  n.value = 6;
  show(n.value); // expect: 6
  o.value = A(1);
  show(o.value);
  // expect: A
  // expect: 1
  m.value += 0.5;
  show(m.value);
  // expect: double
  // expect: 5
  final p = Pair(1, A(2));
  number(p.first); // expect: 1
  number(p.second.n); // expect: 2
  final q = p.swap();
  number(q.first.n); // expect: 2
  number(q.second); // expect: 1
  number(Pair<int, double>(1, 2).first); // expect: 1
  truth(Pair<int, double>(1, 2).second == 2.0); // expect: true
  final nested = Box(Box(Pair(3, 4.5)));
  number(nested.value.value.first); // expect: 3
  nested.value.value = Pair(8, 0);
  number(nested.value.value.first); // expect: 8
  d.value = 3;
  truth(d.value / 2 == 1.5); // expect: true
  Box<double> e = Box(4);
  truth(e.value / 8 == 0.5); // expect: true
  final list = Node(1, Node(2, Node(3)));
  list.each(number);
  // expect: 1
  // expect: 2
  // expect: 3
  number(list.fold(0, (s, t) => s + t)); // expect: 6
  truth(list.fold(true, (s, t) => s && t > 0)); // expect: true
  show(list.fold<num>(0.5, (s, t) => s + t));
  // expect: double
  // expect: 13
  number(i.map((v) => v > 1 ? 1 : 2).value); // expect: 1
  number(i.map(twice).map((v) => A(v)).value.n); // expect: 36
}

void number(int n) => print(n);

void truth(bool b) => print(b);
