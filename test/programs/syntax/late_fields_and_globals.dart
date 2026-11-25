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

int calls = 0;
int next() => ++calls;
late int ga;
late final int gb;
late int gc = next();
late final gd = next();
late P? ge;

class A {
  late int a;
  late final int b;
  late int c = next() + base;
  late final d = next() * base;
  late P? e;
  late final f = this;
  int base;
  static late int sa;
  static late final sb = next();
  late double x;
  late bool y = false;
  A(this.base);
  int use() => c + d;
  late int Function() g = () => a;
}

class B extends A {
  B() : super(100) {
    a = 1;
    b = 2;
  }
  @override
  late int c = 7;
  @override
  int get d => super.d + 1;
  late final A own = A(5);
}

class C {
  late final int n;
  C([int? k]) {
    if (k != null) n = k;
  }
  C.init(this.n);
}

void go(void Function() f) {
  try {
    f();
    print('ok');
  } on Error {
    print('E');
  }
}

void main() {
  go(() => show(ga)); // expect: E
  ga = 1;
  show(ga); // expect: 1
  go(() => show(gb)); // expect: E
  gb = 2;
  go(() => gb = 3); // expect: E
  show(gb); // expect: 2
  show(gc); // expect: 1
  gc = 9;
  show(gc); // expect: 9
  show(gd); // expect: 2
  show(gd); // expect: 2
  go(() => show(ge)); // expect: E
  ge = null;
  show(ge); // expect: null
  go(() => show(A.sa)); // expect: E
  A.sa = 4;
  show(A.sa++); // expect: 4
  show(A.sa); // expect: 5
  show(A.sb); // expect: 3
  final a = A(10);
  go(() => show(a.a)); // expect: E
  a.a = 5;
  show(a.a += 1); // expect: 6
  go(() => show(a.b)); // expect: E
  a.b = 6;
  go(() => a.b = 7); // expect: E
  show(a.b); // expect: 6
  show(a.use()); // expect: 64
  show(a.use()); // expect: 64
  a.c = 1;
  show(a.use()); // expect: 51
  go(() => show(a.e?.n)); // expect: E
  a.e = P(3);
  show(a.e?.n); // expect: 3
  show(a.f == a); // expect: true
  go(() => show(a.x)); // expect: E
  a.x = 2;
  show(a.x);
  // expect: double
  // expect: 4
  show(a.y); // expect: false
  show(a.g()); // expect: 6
  final b = B();
  show(b.a); // expect: 1
  show(b.b); // expect: 2
  show(b.c); // expect: 7
  show(b.d); // expect: 601
  show(b.own.base); // expect: 5
  go(() => b.b = 3); // expect: E
  dynamic d = A(1);
  go(() => show(d.a)); // expect: E
  d.a = 3;
  show(d.a); // expect: 3
  go(() => d.b = 1); // expect: ok
  go(() => d.b = 1); // expect: E
  final c = C();
  go(() => show(c.n)); // expect: E
  c.n = 4;
  go(() => c.n = 5); // expect: E
  show(C(8).n); // expect: 8
  show(C.init(9).n); // expect: 9
  go(() => C.init(9).n = 1); // expect: E
}

void number(int n) => print(n);

void truth(bool b) => print(b);
