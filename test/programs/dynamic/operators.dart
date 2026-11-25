void show(Object? o) {
  if (o == null) {
    tell('null');
  } else if (o is int) {
    number(o);
  } else if (o is bool) {
    truth(o);
  } else if (o is double) {
    tell('double');
    number((o * 2).toInt());
  } else if (o is A) {
    tell('A');
    number(o.n);
  } else {
    tell('other');
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
    tell('ok');
  } on TypeError {
    tell('T');
  } on NoSuchMethodError {
    tell('N');
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

void t(dynamic d, dynamic e) {
  go(() => show(d + e));
  go(() => show(d - e));
  go(() => show(d * e));
  go(() => show(d / e));
  go(() => show(d % e));
  go(() => show(d ~/ e));
  go(() => show(d < e));
  go(() => show(d <= e));
  go(() => show(d > e));
  go(() => show(d >= e));
  go(() => show(d & e));
  go(() => show(d | e));
  go(() => show(d ^ e));
  go(() => show(d << e));
  go(() => show(d >> e));
  go(() => show(d >>> e));
  go(() => show(-d));
  go(() => show(~d));
  go(() => show(d[e]));
  go(() {
    d[e] = e;
  });
  go(() => show(d == e));
  go(() => show(d != e));
  go(() => show(d[e] += 1));
  go(() {
    var x = d;
    x += e;
    show(x);
    x++;
    show(x);
    x ??= 1;
  });
  go(() => show(1 + e));
  go(() => show(1.5 * e));
  go(() => show(d && e));
  go(() => show(!d));
}

void main() {
  for (var i = 0; i < 6; i++) {
    for (var j = 0; j < 6; j++) {
      t(pick(i), pick(j));
      endLine();
    }
  }
  // expect: 14 ok 0 ok 49 ok double 2 ok 0 ok 1 ok false ok true ok false ok true ok 7 ok 7 ok 0 ok 896 ok 0 ok 0 ok -7 ok -8 ok N N true ok false ok N 14 15 ok 8 ok double 21 ok T T
  // expect: double 19 ok double 9 ok double 35 ok double 5 ok double 4 ok 2 ok false ok false ok true ok true ok T T T T T T -7 ok -8 ok N N false ok true ok N double 19 double 21 ok double 7 ok double 7 ok T T
  // expect: T T T T T T T T T T T T T T T T -7 ok -8 ok N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T T T T T T T -7 ok -8 ok N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T T T T T T T -7 ok -8 ok N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T T T T T T T -7 ok -8 ok N N false ok true ok N T T T T T
  // expect: double 19 ok double -9 ok double 35 ok double 0 ok double 5 ok 0 ok true ok true ok false ok false ok N N N N N N double -5 ok N N N false ok true ok N double 19 double 21 ok 8 ok double 21 ok T T
  // expect: double 10 ok double 0 ok double 12 ok double 2 ok double 0 ok 1 ok false ok true ok false ok true ok N N N N N N double -5 ok N N N true ok false ok N double 10 double 12 ok double 7 ok double 7 ok T T
  // expect: T T T T T T T T T T N N N N N N double -5 ok N N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T N N N N N N double -5 ok N N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T N N N N N N double -5 ok N N N false ok true ok N T T T T T
  // expect: T T T T T T T T T T N N N N N N double -5 ok N N N false ok true ok N T T T T T
  // expect: N N N N N N N N N N T T T N N N N N N N false ok true ok N N 8 ok double 21 ok T false ok
  // expect: N N N N N N N N N N T T T N N N N N N N false ok true ok N N double 7 ok double 7 ok T false ok
  // expect: N N N N N N N N N N true ok true ok false ok N N N N N N N true ok false ok N N T T true ok false ok
  // expect: N N N N N N N N N N T T T N N N N N N N false ok true ok N N T T T false ok
  // expect: N N N N N N N N N N T T T N N N N N N N false ok true ok N N T T T false ok
  // expect: N N N N N N N N N N T T T N N N N N N N false ok true ok N N T T T false ok
  // expect: T N N N N N T N N N N N N N N N -3 ok -4 ok 21 ok ok false ok true ok 99 ok T 8 ok double 21 ok T T
  // expect: T N N N N N T N N N N N N N N N -3 ok -4 ok T T false ok true ok T T double 7 ok double 7 ok T T
  // expect: T N N N N N T N N N N N N N N N -3 ok -4 ok T T false ok true ok T T T T T T
  // expect: A 6 ok N N N N N false ok N N N N N N N N N -3 ok -4 ok T T false ok true ok T A 6 T T T T T
  // expect: A 7 ok N N N N N true ok N N N N N N N N N -3 ok -4 ok T T false ok true ok T A 7 T T T T T
  // expect: T N N N N N T N N N N N N N N N -3 ok -4 ok T T false ok true ok T T T T T T
  // expect: T N N N N N T N N N N N N N N N -4 ok -5 ok 28 ok ok false ok true ok 99 ok T 8 ok double 21 ok T T
  // expect: T N N N N N T N N N N N N N N N -4 ok -5 ok T T false ok true ok T T double 7 ok double 7 ok T T
  // expect: T N N N N N T N N N N N N N N N -4 ok -5 ok T T false ok true ok T T T T T T
  // expect: A 7 ok N N N N N false ok N N N N N N N N N -4 ok -5 ok T T false ok true ok T A 7 T T T T T
  // expect: A 8 ok N N N N N false ok N N N N N N N N N -4 ok -5 ok T T false ok true ok T A 8 T T T T T
  // expect: T N N N N N T N N N N N N N N N -4 ok -5 ok T T false ok true ok T T T T T T
  // expect: N N N N N N N N N N N N N N N N N N N N false ok true ok N N 8 ok double 21 ok T T
  // expect: N N N N N N N N N N N N N N N N N N N N false ok true ok N N double 7 ok double 7 ok T T
  // expect: N N N N N N N N N N N N N N N N N N N N false ok true ok N N T T T T
  // expect: N N N N N N N N N N N N N N N N N N N N false ok true ok N N T T T T
  // expect: N N N N N N N N N N N N N N N N N N N N false ok true ok N N T T T T
  // expect: N N N N N N N N N N N N N N N N N N N N true ok false ok N N T T T T
  go(() => show(1));
  endLine(); // expect: 1 ok
}

/// What is told on one line.
final told = <Object?>[];

void tell(Object? o) => told.add(o);

void endLine() {
  print(told.join(' '));
  told.clear();
}

void number(int n) => tell(n);

void truth(bool b) => tell(b);
