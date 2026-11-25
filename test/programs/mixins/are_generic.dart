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
  } else {
    print('other');
  }
}

class Base<T> {
  T? t;
  T? get() => t;
}

mixin Store<T> on Base<T> {
  T? old;
  void put(T v) {
    old = t;
    t = v;
  }

  bool has(Object? o) => o is T;
  @override
  T? get() => super.get() ?? old;
}

mixin Pairs<X, Y> {
  X? a;
  Y? b;
  bool ok(Object? o) => o is X && o is! Y;
  List1<X> make() => List1<X>();
  Y second(Y y) => b = y;
}

class List1<E> {
  bool holds(Object? o) => o is E;
}

class I extends Base<int> with Store<int> {}

class G<T> extends Base<T> with Store<T>, Pairs<T, bool> {}

class P with Pairs<int, double> {}

class Q = G<num> with Pairs<num, bool>;
void go(void Function() f) {
  try {
    f();
    print('ok');
  } on TypeError {
    print('T');
  }
}

void main() {
  final i = I();
  i.put(3);
  i.put(4);
  show(i.old); // expect: 3
  show(i.get()); // expect: 4
  truth(i.has(1)); // expect: true
  truth(i.has(1.5)); // expect: false
  final g = G<num>();
  g.put(1.5);
  show(g.get());
  // expect: double
  // expect: 3
  truth(g.has(2)); // expect: true
  truth(g.ok(2)); // expect: true
  truth(g.make().holds(1.5)); // expect: true
  final p = P();
  truth(p.ok(1)); // expect: true
  truth(p.ok(1.5)); // expect: false
  p.a = 5;
  show(p.a); // expect: 5
  show(p.second(2));
  // expect: double
  // expect: 4
  Store<num> s = i;
  go(() => s.put(1.5)); // expect: T
  go(() => s.put(8)); // expect: ok
  Object o = g;
  truth(o is Pairs<num, bool>); // expect: true
  truth(o is Pairs<int, bool>); // expect: false
  truth(o is Pairs<Object, Object>); // expect: true
  truth(o is Store<int>); // expect: false
  Pairs<Object, Object> w = p;
  go(() => w.second(1)); // expect: T
  go(() => w.a = true); // expect: T
  dynamic d = g;
  go(() => d.put(true)); // expect: T
  go(() => d.put(2)); // expect: ok
  go(() => show(d.old));
  // expect: double
  // expect: 3
  // expect: ok
  final f = g.second;
  go(() => show(f(true)));
  // expect: true
  // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
