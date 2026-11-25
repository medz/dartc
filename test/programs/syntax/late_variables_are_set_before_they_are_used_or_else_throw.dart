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
void go(void Function() f) {
  try {
    f();
    print('ok');
  } on Error {
    print('E');
  }
}

void main() {
  late int a;
  void ra() => show(a);
  go(ra); // expect: E
  a = 3;
  show(a); // expect: 3
  a = 4;
  show(a); // expect: 4
  late final int b;
  go(() => show(b)); // expect: E
  void sb(int n) => b = n;
  sb(5);
  show(b); // expect: 5
  go(() => sb(6)); // expect: E
  show(b); // expect: 5
  late int c = next();
  show(calls); // expect: 0
  show(c); // expect: 1
  show(c); // expect: 1
  c = 9;
  show(c); // expect: 9
  late final d = next();
  show(d); // expect: 2
  show(d); // expect: 2
  show(calls); // expect: 2
  late int e = next();
  e = 1;
  show(e); // expect: 1
  show(calls); // expect: 2
  late P? p;
  go(() => show(p?.n)); // expect: E
  p = null;
  show(p?.n); // expect: null
  p = P(1);
  show(p.n); // expect: 1
  late Object? o;
  go(() => show(o)); // expect: E
  o = null;
  show(o); // expect: null
  late double x;
  x = 1.5;
  show(x);
  // expect: double
  // expect: 3
  late bool y = calls > 1;
  show(y); // expect: true
  late final int? z;
  go(() => show(z)); // expect: E
  void sz(int? n) {
    z = n;
  }

  sz(null);
  show(z); // expect: null
  go(() => sz(1)); // expect: E
  for (var i = 0; i < 2; i++) {
    late int k;
    go(() => show(k));
    k = i;
    show(k);
    late final int m = next();
    show(m);
  }
  // expect: E
  // expect: 0
  // expect: 3
  // expect: E
  // expect: 1
  // expect: 4
  late int Function(int) f;
  f = (n) => n < 2 ? 1 : n * f(n - 1);
  show(f(5)); // expect: 120
  late void Function() g = () => show(calls);
  g(); // expect: 4
  late int u, v = 2;
  u = v;
  show(u); // expect: 2
  int w() {
    late int q;
    void set() {
      q = 8;
    }

    go(() => show(q));
    set();
    return q;
  }

  show(w());
  // expect: E
  // expect: 8
  late String2 s = String2();
  s.n++;
  show(s.n); // expect: 1
}

class String2 {
  int n = 0;
}

void number(int n) => print(n);

void truth(bool b) => print(b);
