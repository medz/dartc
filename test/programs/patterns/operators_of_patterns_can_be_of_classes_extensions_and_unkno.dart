class Base {
  final int v;
  Base(this.v);
}

extension BaseOps on Base {
  bool operator >(int o) => v > o;
  bool operator <=(int o) => v <= o;
}

extension NOps on String? {
  bool operator <(String? o) => (this?.length ?? 0) < (o?.length ?? 0);
}

class Money implements Comparable<Money> {
  final int c;
  const Money(this.c);
  bool operator >(Money o) => c > o.c;
  bool operator <(Object o) => o is Money && c < o.c;
  @override
  int compareTo(Money o) => c - o.c;
}

class NE {
  final int n;
  const NE(this.n);
  @override
  bool operator ==(Object o) => o is NE && n == o.n;
  @override
  int get hashCode => n;
}

String f(Object? o) => switch (o) {
  Base() && > 3 => 'big',
  Base() && <= 1 => 'small',
  Base() => 'mid',
  Money() && > const Money(5) => 'rich',
  Money() && < const Money(2) => 'poor',
  int() && > 10 && < 20 => 'teen',
  double() && >= 2 => 'd',
  == const NE(3) => 'ne',
  != null => 'other',
  _ => 'null',
};
String g(String? s) => switch (s) {
  < 'ab' => 'short',
  _ => 'long',
};
String h(num n) => switch (n) {
  < 2 => 'a',
  >= 2.5 => 'b',
  _ => 'c',
};
String k(dynamic n) => switch (n) {
  < 2 => 'a',
  >= 2.5 => 'b',
  _ => 'c',
};
T id<T extends num>(T x) {
  if (x case > 3) print('gt');
  return x;
}

String m(int? n) => switch (n) {
  int() && > 3 => 'y',
  null => 'n',
  _ => 'z',
};
void main() {
  for (final o in [
    Base(4),
    Base(1),
    Base(2),
    const Money(6),
    const Money(1),
    const Money(3),
    15,
    30,
    2.5,
    1.0,
    const NE(3),
    const NE(4),
    null,
  ])
    print(f(o));
  // expect: big
  // expect: small
  // expect: mid
  // expect: rich
  // expect: poor
  // expect: other
  // expect: teen
  // expect: other
  // expect: d
  // expect: other
  // expect: ne
  // expect: other
  // expect: null
  print((
    g(null),
    g('abc'),
    h(1),
    h(2),
    h(3),
    k(1),
    k(2.2),
    k(9),
    id(5),
    id(2.5),
    m(4),
    m(null),
    m(1),
  ));
  // expect: gt
  // expect: (short, long, a, c, b, a, c, b, 5, 2.5, y, n, z)
}
