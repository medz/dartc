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

void main() {
  for (var i = 0; i < 3; i++) {
    final p = pick(i);
    show(p?.next?.n);
    show(p?.next?.next?.twice);
    show(p?.add(trace(1)).add(trace(2)).n);
    show(p?.list?.self()?.len);
    show(p?.add(1).maybe(true)!.n);
    print('-');
  }
  // expect: pick
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: -
  // expect: pick
  // expect: null
  // expect: null
  // expect: 1
  // expect: 2
  // expect: 4
  // expect: null
  // expect: 5
  // expect: -
  // expect: pick
  // expect: 3
  // expect: 8
  // expect: 1
  // expect: 2
  // expect: 5
  // expect: 0
  // expect: 6
  // expect: -
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
