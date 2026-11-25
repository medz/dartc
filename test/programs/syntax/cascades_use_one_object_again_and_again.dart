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

P make() {
  print('make');
  return P(1);
}

void main() {
  final p = make()
    ..add(2)
    ..n += 3
    ..add(trace(4)).add(1)
    ..s = 5
    ..next = P(9);
  // expect: make
  // expect: 4
  // expect: 5
  number(p.n); // expect: 11
  number(p.next?.n ?? 0); // expect: 9
  final q = P(2)
    ..[1] = 7
    ..[trace(2)] += 1
    ..n += 1; // expect: 2
  number(q.n); // expect: 41
  number((P(3)..n *= 2).twice); // expect: 12
  number(
    (P(5)
              ..list = (List1()
                ..add(6)
                ..add(7)))
            .list
            ?.len ??
        -1,
  ); // expect: 2
  var r = P(1)..f = number;
  r
    ..f!(3)
    ..f?.call(4)
    ..next = (P(8)..n = 1);
  // expect: 3
  // expect: 4
  r.next!
    ..n = 4
    ..add(1);
  number(r.next!.n); // expect: 5
  P(1)
    ..add(1)
    ..call()
    ..call();
  // expect: call
  // expect: call
  P(4)
    ..next?.n = 3
    ..next ??= P(6)
    ..next!.n += 1;
  dynamic d = P(1);
  d
    ..n = 5
    ..add(2)
    ..next = P(1);
  show(d.n); // expect: 7
  (d..n = 8).add(1);
  number(d.n); // expect: 9
  final s = (p + 1)..n -= 2;
  number(s.n); // expect: 10
  true ? (P(1)..add(1)) : P(2);
  var x = P(1)..twice;
  number(x.n); // expect: 1
}

void number(int n) => print(n);

void truth(bool b) => print(b);

int trace(int n) {
  print(n);
  return n;
}
