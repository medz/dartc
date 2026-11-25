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
  int n;
  A(this.n);
  int add(int m, [int k = 100]) => n + m + k;
  num named({required int a, num b = 2}) => n * a + b;
  void shout() {
    number(n);
  }

  int get twice => n * 2;
  set twice(int v) {
    n = v ~/ 2;
  }

  A operator +(A o) => A(n + o.n);
  int operator [](int i) => n * i;
  void operator []=(int i, num v) {
    n = i + v.toInt();
  }

  int operator -() => -n;
  bool operator <(covariant A o) => n < o.n;
  int Function(int) get f =>
      (x) => x + n;
  Object? any = 5;
  int operator ~() => ~n;
  int call(int x, {int y = 1}) => n * 100 + x * 10 + y;
  int _p = 9;
  int _q() => _p;
}

class B extends A {
  B(super.n);
  @override
  int add(Object? m, [Object? k = 1, int z = 2]) => m is int ? m + z : -1;
  int only() => 7;
}

class G<T> {
  T? t;
  void put(T v) {
    t = v;
  }

  T get() => t as T;
  bool has(Object? o) => o is T;
  S id<S>(S s) => s;
  bool isS<S>(Object? o) => o is S;
}

int twice(int n) => n * 2;
int opt(int a, {int b = 1}) => a * 10 + b;
void go(void Function() f) {
  try {
    f();
    print('ok');
  } on TypeError {
    print('T');
  } on NoSuchMethodError {
    print('N');
  }
}

dynamic pick(int n) {
  switch (n) {
    case 0:
      return 7;
    case 1:
      return 2.5;
    case 2:
      return true;
    case 3:
      return A(3);
    case 4:
      return B(4);
    case 5:
      return null;
    case 6:
      return twice;
    case 7:
      return G<int>();
  }
  return opt;
}

class P<T> extends G<T> {
  void both(T a, G<T> g) {
    show(a);
  }

  T Function(T) fn() =>
      (t) => t;
}

void main() {
  dynamic g = G<int>();
  go(() => g.put(1)); // expect: ok
  go(() => g.put(1.5)); // expect: T
  go(() => show(g.get()));
  // expect: 1
  // expect: ok
  go(() => show(g.t));
  // expect: 1
  // expect: ok
  go(() => g.t = true); // expect: T
  go(() => g.t = null); // expect: ok
  go(() => show(g.has(2)));
  // expect: true
  // expect: ok
  go(() => show(g.has(2.5)));
  // expect: false
  // expect: ok
  go(() => show(g.id(6)));
  // expect: 6
  // expect: ok
  go(() => show(g.isS(6)));
  // expect: true
  // expect: ok
  dynamic p = P<num>();
  go(() => p.both(1, G<num>()));
  // expect: 1
  // expect: ok
  go(() => p.both(1, G<int>()));
  // expect: 1
  // expect: ok
  go(() => p.both(true, G<num>())); // expect: T
  go(() => show(p.fn()(2)));
  // expect: 2
  // expect: ok
  go(() => show(p.fn()(true))); // expect: T
  go(() => show((p.put)(true))); // expect: T
  go(() => p.both(1, G<Object>())); // expect: T
  dynamic f = P<int>().fn();
  go(() => show(f(3)));
  // expect: 3
  // expect: ok
  go(() => show(f(3.5))); // expect: T
  dynamic q = P<int>().put;
  go(() => q(1)); // expect: ok
  go(() => q(1.5)); // expect: T
  dynamic h = twice;
  go(() => show(h is int Function(int)));
  // expect: true
  // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
