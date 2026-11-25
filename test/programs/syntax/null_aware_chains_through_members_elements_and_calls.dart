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
    show(p?[trace(1)]);
    show(p?.next?[2]);
    show(p?.add(1)[3]);
    show(p?.maybe(true)?.add(2)[trace(4)]);
    show(p?.list?[5]);
    p?.f?.call(1);
    p?.f = number;
    p?.f?.call(trace(6));
    p?.f!(7);
    p?.next?.call();
    p?.call();
    show((p?.next)?.n);
    show(p?.maybe(false)?.n);
    show(p?.none?.toDouble());
    show(p?.d?.n);
    show(p?.twice.toDouble());
    show(-(p?.n ?? 4));
    show(p?.n == null);
    if (p?.n == 2) print('two');
    if (p?.next != null) print('next');
    final f = p?.add;
    show(f?.call(5).n);
    int? t = p?.n;
    show(t);
    show(p?.next?.next?.next?.n);
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
  // expect: -4
  // expect: true
  // expect: null
  // expect: null
  // expect: null
  // expect: -
  // expect: pick
  // expect: 1
  // expect: 2
  // expect: null
  // expect: 5
  // expect: 4
  // expect: 8
  // expect: null
  // expect: 6
  // expect: 6
  // expect: 7
  // expect: call
  // expect: null
  // expect: null
  // expect: null
  // expect: null
  // expect: double
  // expect: 16
  // expect: -4
  // expect: false
  // expect: 9
  // expect: 9
  // expect: null
  // expect: -
  // expect: pick
  // expect: 1
  // expect: 3
  // expect: 5
  // expect: 6
  // expect: 4
  // expect: 9
  // expect: 5
  // expect: 6
  // expect: 6
  // expect: 7
  // expect: call
  // expect: call
  // expect: 3
  // expect: null
  // expect: null
  // expect: null
  // expect: double
  // expect: 20
  // expect: -5
  // expect: false
  // expect: next
  // expect: 10
  // expect: 10
  // expect: null
  // expect: -
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
