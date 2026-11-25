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
    p?.n = trace(1);
    show(p?.n);
    show(p?.n = trace(2));
    p?.n += trace(3);
    show(p?.n++);
    show(++p?.n);
    p?.next?.n = trace(4);
    show(p?.next?.n);
    p?.next?.next?.n -= 1;
    show(p?.next?.next?.n);
    p?[trace(5)] = trace(6);
    show(p?.n);
    p?[1] += trace(7);
    show(p?.n);
    p?.next ??= P(70);
    show(p?.next?.n);
    p?.next?.next ??= P(trace(80));
    p?.list?[1] = trace(8);
    show(p?.list?.len);
    p?.d = 5;
    p?.d += 1;
    show(p?.d);
    p?.d ??= 3;
    p?.s = trace(9);
    p?.add(1).n = 100;
    show(p?.n);
    p?.list?.x ??= trace(11);
    show(p?.list?.x);
    print('-');
  }
  // expect: pick
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: -
  // expect: pick
  // expect: 1
  // expect: 1
  // expect: 2
  // expect: 2
  // expect: 3
  // expect: 5
  // expect: 7
  // expect: null
  // expect: null
  // expect: 5
  // expect: 6
  // expect: 56
  // expect: 7
  // expect: 74
  // expect: 70
  // expect: 80
  // expect: null
  // expect: 6
  // expect: 9
  // expect: 9
  // expect: 100
  // expect: null
  // expect: -
  // expect: pick
  // expect: 1
  // expect: 1
  // expect: 2
  // expect: 2
  // expect: 3
  // expect: 5
  // expect: 7
  // expect: 4
  // expect: 4
  // expect: 3
  // expect: 5
  // expect: 6
  // expect: 56
  // expect: 7
  // expect: 74
  // expect: 4
  // expect: 8
  // expect: 8
  // expect: 6
  // expect: 9
  // expect: 9
  // expect: 100
  // expect: 11
  // expect: 11
  // expect: -
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
