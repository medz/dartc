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

class S {
  static P? p;
  static int n = 1;
}

P? g;
void main() {
  show(S.p?.n); // expect: null
  S.p = P(4);
  show(S.p?.add(1).n); // expect: 5
  S.p?.n = 9;
  show(S.p?.n); // expect: 9
  g?.n = 3;
  show(g?.n); // expect: null
  g = P(1);
  g?.next?.n = 4;
  g?.next = P(2);
  show(g?.next?.n); // expect: 2
  dynamic d;
  show(d?.n); // expect: null
  show(d?.add(1).n); // expect: null
  show(d?.foo.bar[3].baz()); // expect: null
  d?.n = trace(1);
  d?[trace(2)] = 3;
  show(d?[0]); // expect: null
  d = P(5);
  show(d?.add(1).n); // expect: 6
  d?.n = trace(8); // expect: 8
  show(d?[1]); // expect: 9
  d?[1] = trace(2); // expect: 2
  show(d?.n); // expect: 12
  show(d?.next?.n); // expect: null
  show(d?.maybe(true)?.n); // expect: 12
  Function? f;
  show(f?.call(trace(1))); // expect: null
  f = (int n) => n + 1;
  show(f?.call(trace(1)));
  // expect: 1
  // expect: 2
  P? Function()? h;
  show(h?.call()?.n); // expect: null
  h = () => P(6);
  show(h?.call()?.n); // expect: 6
  show(h()?.add(1).n); // expect: 7
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
