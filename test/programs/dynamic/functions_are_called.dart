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

void t(dynamic d, Function? f) {
  go(() => show(d(1)));
  go(() => show(d(1, b: 2)));
  go(() => show(d(1, y: 2)));
  go(() => show(d()));
  go(() => show(d(1.5)));
  go(() => show(d(true, 2)));
  go(() => show(d.call(3)));
  go(() => show((d.call)(4)));
  if (f != null) {
    go(() => show(f(1)));
    go(() => show(f()));
    go(() => show(f(1.5)));
    go(() => show(f(1, b: 3)));
    go(() => show(f.call(2)));
  }
}

void main() {
  for (var i = 0; i < 9; i++) {
    final p = pick(i);
    t(p, p is Function ? p : null);
    print('-');
  }
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: -
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: -
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: -
  // expect: 311
  // expect: ok
  // expect: N
  // expect: 312
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 331
  // expect: ok
  // expect: 341
  // expect: ok
  // expect: -
  // expect: 411
  // expect: ok
  // expect: N
  // expect: 412
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 431
  // expect: ok
  // expect: 441
  // expect: ok
  // expect: -
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: -
  // expect: 2
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: 6
  // expect: ok
  // expect: 8
  // expect: ok
  // expect: 2
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 4
  // expect: ok
  // expect: -
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: -
  // expect: 11
  // expect: ok
  // expect: 12
  // expect: ok
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: 31
  // expect: ok
  // expect: 41
  // expect: ok
  // expect: 11
  // expect: ok
  // expect: N
  // expect: T
  // expect: 13
  // expect: ok
  // expect: 21
  // expect: ok
  // expect: -
  t((int x) => x + 1, null);
  // expect: 2
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: 4
  // expect: ok
  // expect: 5
  // expect: ok
  t(([int x = 4]) => x, null);
  // expect: 1
  // expect: ok
  // expect: N
  // expect: N
  // expect: 4
  // expect: ok
  // expect: T
  // expect: N
  // expect: 3
  // expect: ok
  // expect: 4
  // expect: ok
  t(({required num b}) => b, null);
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  t(() {}, null);
  // expect: N
  // expect: N
  // expect: N
  // expect: null
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: N
  t(A(5).add, A(6).add);
  // expect: 106
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: T
  // expect: 108
  // expect: ok
  // expect: 109
  // expect: ok
  // expect: 107
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 108
  // expect: ok
  t(A.new, B.new);
  // expect: A
  // expect: 1
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: A
  // expect: 3
  // expect: ok
  // expect: A
  // expect: 4
  // expect: ok
  // expect: A
  // expect: 1
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: A
  // expect: 2
  // expect: ok
  t((x) => x, (x, {b}) => b);
  // expect: 1
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: double
  // expect: 3
  // expect: ok
  // expect: N
  // expect: 3
  // expect: ok
  // expect: 4
  // expect: ok
  // expect: null
  // expect: ok
  // expect: N
  // expect: null
  // expect: ok
  // expect: 3
  // expect: ok
  // expect: null
  // expect: ok
  int local(int n) => n * 3;
  t(local, local);
  // expect: 3
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: 9
  // expect: ok
  // expect: 12
  // expect: ok
  // expect: 3
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 6
  // expect: ok
  dynamic n = 5;
  final g = (int k) => k + (n as int);
  t(g, g);
  // expect: 6
  // expect: ok
  // expect: N
  // expect: N
  // expect: N
  // expect: T
  // expect: N
  // expect: 8
  // expect: ok
  // expect: 9
  // expect: ok
  // expect: 6
  // expect: ok
  // expect: N
  // expect: T
  // expect: N
  // expect: 7
  // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
