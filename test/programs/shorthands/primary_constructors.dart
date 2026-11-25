int trace(int n) {
  print('t$n');
  return n;
}

class Point(final int x, var int y) {
  int get sum => x + y;
  String toString() => '($x, $y)';
}

class const Fixed(final int n, {final String name = 'none'});
class Empty();

class Base(final int a) {
  Base.twice(int n) : this(n * 2);
}

class Sub(int a, final int b) extends Base {
  this : super(a + 1);
  final int c = a * 10;
  late final int d = c + b;
}

class Super(super.a, {required final int k}) extends Base;

class Checked(final int n) {
  final int twice;
  this : assert(n > 0), twice = trace(n * 2) {
    print('body $n $twice');
    count++;
  }
  static int count = 0;
}

class Named.make(final String s, [int times = 2]) {
  final String all = s * times;
  factory Named(String s) => Named.make('<$s>');
}

class Generic<T>(final T value, final List<T> more) {
  Type get type => T;
  final int length = more.length;
}

class Order(int p) {
  final int first = trace(p + 1);
  final int second = trace(p + 2);
  int third;
  this : third = trace(p + 3) {
    print('end $third');
  }
}

class Private({required this._x, int y = 1}) {
  final int _x;
  final int z = y + 1;
}

class Over(final int x) implements Comparable<Over> {
  @override
  int compareTo(Over o) => x - o.x;
}

abstract class Abs(final int v) {
  int get w;
}

class Impl(super.v) extends Abs {
  int get w => v + 1;
}

enum Size(final int n) {
  small(1),
  large(10);

  int get d => n * 2;
}

enum Planet { a, b }

extension type Id(int n) {
  int get next => n + 1;
}

extension type Pos(int n) {
  this {
    if (n < 0) throw ArgumentError('neg');
    print('pos $n');
  }
}

mixin M {
  int get m => 5;
}

class Mixed(final int q) with M;

class Closer(int n) {
  final int Function() get = () => n;
  void Function()? f;
  this {
    f = () => n + 10;
  }
}

void main() {
  final p = Point(1, 2);
  p.y = 5;
  print(p); // expect: (1, 5)
  print(p.sum); // expect: 6
  print(const Fixed(3).name); // expect: none
  print(identical(const Fixed(1), const Fixed(1))); // expect: true
  print(Fixed(2, name: 'q').name); // expect: q
  Empty();
  final s = Sub(1, 2);
  print('${s.a} ${s.b} ${s.c} ${s.d}'); // expect: 2 2 10 12
  print(Super(4, k: 9).a); // expect: 4
  print(Super(4, k: 9).k); // expect: 9
  print(Base.twice(4).a); // expect: 8
  final c = Checked(4);
  // expect: t8
  // expect: body 4 8
  print(c.twice); // expect: 8
  print(Checked.count); // expect: 1
  print(Named('x').all); // expect: <x><x>
  print(Named.make('y', 3).all); // expect: yyy
  final g = Generic(1, [2, 3]);
  print(g.type); // expect: int
  print(g.length); // expect: 2
  final o = Order(10);
  // expect: t11
  // expect: t12
  // expect: t13
  // expect: end 13
  print(o.first + o.second); // expect: 23
  print(Private(x: 3)._x); // expect: 3
  print(Private(x: 3, y: 4).z); // expect: 5
  print((<Over>[Over(3), Over(1)]..sort()).first.x); // expect: 1
  print(Impl(3).w); // expect: 4
  print(Size.large.d); // expect: 20
  print(Size.values); // expect: [Size.small, Size.large]
  print(Id(3).next); // expect: 4
  print(Pos(2).n);
  // expect: pos 2
  // expect: 2
  try {
    Pos(-1);
  } catch (e) {
    print(e);
  }
  // expect: Invalid argument(s): neg
  print(Mixed(1).m); // expect: 5
  final cl = Closer(5);
  print(cl.get()); // expect: 5
  cl.f!();
  final make = Point.new;
  print(make(7, 8)); // expect: (7, 8)
  print(Generic<num>(1, []).type); // expect: num
}
