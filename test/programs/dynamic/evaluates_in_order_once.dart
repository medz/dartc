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

dynamic get d {
  print('d');
  return A(1);
}

int n(int k) {
  number(k);
  return k;
}

void main() {
  d.add(n(1), n(2));
  // expect: d
  // expect: 1
  // expect: 2
  d.named(b: n(3), a: n(4));
  // expect: d
  // expect: 3
  // expect: 4
  d.n = n(5);
  // expect: d
  // expect: 5
  d.n += n(6);
  // expect: d
  // expect: 6
  d[n(7)] = n(8);
  // expect: d
  // expect: 7
  // expect: 8
  d[n(9)] += n(10);
  // expect: d
  // expect: 9
  // expect: 10
  go(() => d.missing(n(11)));
  // expect: d
  // expect: 11
  // expect: N
  go(() => d.missing = n(12));
  // expect: d
  // expect: 12
  // expect: N
}

void number(int n) => print(n);

void truth(bool b) => print(b);
