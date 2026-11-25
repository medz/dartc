enum Color {
  red,
  green;

  static Color pick(int n) => values[n];
  static Color get best => green;
  static const fav = red;
}

class Box {
  final int n;
  const Box(this.n);
  Box.twice(int k) : n = k * 2;
  factory Box.zero() => const .new(0);
  static Box max = Box(99);
  static Box of(int n) => Box(n);
  Box operator +(Box o) => Box(n + o.n);
  Box get next => Box(n + 1);
  Box add(int k) => .new(n + k);
  @override
  bool operator ==(Object o) => o is Box && o.n == n;
  @override
  int get hashCode => n;
}

class G<T> {
  final T v;
  G(this.v);
  G.list(List<T> l) : v = l.first;
  static G<int> one() => G(1);
}

extension type Meter(int m) {
  static Meter get zero => Meter(0);
  Meter.km(int k) : m = k * 1000;
}

void take(Color c, {Box box = const .new(5)}) => print('$c ${box.n}');
Color get ret => .green;
Box make() {
  return .twice(4);
}

void main() {
  Color c = .red;
  print(c); // expect: Color.red
  c = .green;
  print(c == .green); // expect: true
  print(c != .red); // expect: true
  Color d = .pick(0);
  print(d); // expect: Color.red
  d = .best;
  print(d); // expect: Color.green
  d = .fav;
  print(d); // expect: Color.red
  take(.red); // expect: Color.red 5
  take(.green, box: .new(7)); // expect: Color.green 7
  take(.red, box: .max); // expect: Color.red 99
  print(ret); // expect: Color.green
  print(make().n); // expect: 8
  Box b = .zero();
  print(b.n); // expect: 0
  b = .of(3).next.add(4);
  print(b.n); // expect: 8
  Box e = Box(1) + .new(2);
  print(e.n); // expect: 3
  const Box k = .new(8);
  print(k.n); // expect: 8
  Box q = const .new(3);
  print(q.n); // expect: 3
  List<Color> l = [.red, .green, if (c == .green) .red];
  print(l); // expect: [Color.red, Color.green, Color.red]
  Map<Color, Box> m = {.red: .new(1)};
  print(m[Color.red]!.n); // expect: 1
  switch (c) {
    case .red:
      print('r');
    case .green:
      print('g');
  }
  // expect: g
  print(switch (c) {
    .red => 1,
    .green => 2,
  }); // expect: 2
  G<int> g = .new(4);
  print(g.v); // expect: 4
  G<String> h = .list(['a']);
  print(h.v); // expect: a
  G<int> i = .one();
  print(i.v); // expect: 1
  Meter z = .zero;
  print(z.m); // expect: 0
  z = .km(2);
  print(z.m); // expect: 2000
  Color? n = c == .red ? null : .green;
  print(n); // expect: Color.green
  Object o = c;
  print(o == Color.green); // expect: true
  Future<int>? fu;
  print(fu); // expect: null
  int x = .parse('42');
  print(x); // expect: 42
  double y = .infinity;
  print(y); // expect: Infinity
  Duration t = .zero;
  print(t); // expect: 0:00:00.000000
  final s = <Duration>[.new(seconds: 2)];
  print(s); // expect: [0:00:02.000000]
  if (o case Color.green) print('is'); // expect: is
  print([Box(1), Box(2)].contains(const Box(2))); // expect: true
  BigInt bi = .from(5);
  print(bi); // expect: 5
  String str = .fromCharCode(65);
  print(str); // expect: A
}
