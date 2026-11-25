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

class P {
  int n;
  P? next;
  List1? list;
  void Function(int)? f;
  dynamic d;
  P(this.n, [this.next]);
  int get twice => n * 2;
  P add(int k) {
    n += k;
    return this;
  }

  P? maybe(bool b) => b ? this : null;
  int operator [](int i) => n + i;
  void operator []=(int i, int v) {
    n = i * 10 + v;
  }

  set s(int v) {
    number(v);
  }

  void call() {
    print('call');
  }

  P operator +(int k) => P(n + k);
  int? get none => null;
}

class List1 {
  int? x;
  P? p = P(50);
  int len = 0;
  void add(int v) {
    len++;
    x = v;
  }

  List1? self() => this;
  int operator [](int i) => len + i;
  void operator []=(int i, int v) {
    len = v;
  }
}

P? pick(int n) {
  print('pick');
  switch (n) {
    case 0:
      return null;
    case 1:
      return P(1);
  }
  final p = P(2, P(3, P(4)));
  p.list = List1();
  p.next?.list = List1();
  return p;
}

int n = 0;
int f() {
  if (++n < 3) throw P(n);
  return n;
}

late int a = f();

class A {
  late int b = f();
  late final int c = g();
  int g() {
    if (n > 100) {
      n -= 60;
      return c + 1;
    }
    return 6;
  }

  late int d = h();
  int h() {
    d = 8;
    return 9;
  }
}

void go(void Function() f) {
  try {
    f();
    print('ok');
  } on P catch (p) {
    show(p.n);
  } on Error {
    print('E');
  }
}

void main() {
  go(() => show(a)); // expect: 1
  go(() => show(a)); // expect: 2
  go(() => show(a));
  // expect: 3
  // expect: ok
  go(() => show(a));
  // expect: 3
  // expect: ok
  n = 0;
  final o = A();
  go(() => show(o.b)); // expect: 1
  go(() => show(o.b)); // expect: 2
  go(() => show(o.b));
  // expect: 3
  // expect: ok
  go(() => show(o.c));
  // expect: 6
  // expect: ok
  n = 200;
  go(() => show(A().c)); // expect: E
  go(() => show(o.d));
  // expect: 9
  // expect: ok
  late int k = f();
  n = 1;
  go(() => show(k)); // expect: 2
  go(() => show(k));
  // expect: 3
  // expect: ok
}

void number(int n) => print(n);

void truth(bool b) => print(b);
