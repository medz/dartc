import 'dart:math' as m;

enum Level {
  low(1),
  high(10);

  final int n;
  const Level(this.n);
  static const all = [low, high];
  static const map = {low: 'l', high: 'h'};
}

class Conf {
  final Level level;
  final List<Level> more;
  const Conf(this.level, [this.more = const [Level.low]]);
}

const conf = Conf(Level.high);

extension LevelX on Level {
  Level get other => this == Level.low ? Level.high : Level.low;
  static Level parse(String s) => Level.values.firstWhere((l) => l.name == s);
}

extension OnFn on void Function(int) {
  void twice(int n) {
    this(n);
    this(n + 1);
  }

  void callAll(List<int> l) => l.forEach(this);
}

extension on num {
  num get sq => this * this;
  Comparable<num> get c => this;
}

extension Nums<T extends num> on Iterable<T> {
  num get total => fold<num>(0, (a, b) => a + b);
  T get biggest => reduce((a, b) => m.max(a, b));
}

extension Opt<T extends Object> on T? {
  R? map<R>(R Function(T) f) {
    final self = this;
    return self == null ? null : f(self);
  }

  T get must => this!;
}

extension Phantom on bool {
  int get asInt => this ? 1 : 0;
  bool operator [](bool o) => this && o;
}

sealed class S {}

enum Planet implements Comparable<Planet> {
  a,
  b;

  @override
  int compareTo(Planet o) => index.compareTo(o.index);
  bool operator <(Planet o) => compareTo(o) < 0;
}

mixin M on Enum {
  String get tag => '${index}-$name';
}

enum WithM with M { x, y }

enum G<T> {
  i<int>(),
  s<String>();

  const G();
  List<T> make() => <T>[];
  static G<int> one() => i;
}

class Holder<E extends Enum> {
  final List<E> values;
  Holder(this.values);
  E next(E e) => values[(e.index + 1) % values.length];
}

abstract class Base {
  int get v;
}

extension BaseX on Base {
  int get vv => v * 2;
  void run() {
    void inner() {
      print(vv + v);
      print(this.vv);
    }

    inner();
  }
}

class Impl extends Base {
  int v = 4;
  void test() {
    print(vv);
    run();
  }
}

void main() {
  print(conf.level.n); // expect: 10
  print(conf.more); // expect: [Level.low]
  print(Level.all); // expect: [Level.low, Level.high]
  print(Level.map); // expect: {Level.low: l, Level.high: h}
  print(conf.level.other); // expect: Level.low
  print(LevelX.parse('low')); // expect: Level.low
  final f = LevelX.parse;
  print(f('high')); // expect: Level.high
  ((int n) => print('n$n')).twice(3);
  // expect: n3
  // expect: n4
  void g(int n) => print('g$n');
  g.twice(7);
  // expect: g7
  // expect: g8
  g.callAll([1, 2]);
  // expect: g1
  // expect: g2
  (print as void Function(int)).twice(0);
  // expect: 0
  // expect: 1
  print(3.sq); // expect: 9
  print(2.5.sq); // expect: 6.25
  num q = 4;
  print(q.sq); // expect: 16
  print(q.c.compareTo(3)); // expect: 1
  print([1, 2, 3].total); // expect: 6
  print([1.5, 2].total); // expect: 3.5
  print([1, 5, 2].biggest); // expect: 5
  print(<double>[1, 0].biggest); // expect: 1.0
  int? a = conf.level.n > 100 ? null : 5;
  print(a.map((x) => x + 1)); // expect: 6
  String? z = conf.level.n > 1 ? null : '';
  print(z.map((s) => s.length)); // expect: null
  try {
    z.must;
  } catch (e) {
    print(e);
  }
  // expect: Null check operator used on a null value
  print(a.must); // expect: 5
  print(true.asInt); // expect: 1
  print(true[false]); // expect: false
  print(Planet.a < Planet.b); // expect: true
  print([Planet.b, Planet.a]..sort()); // expect: [Planet.a, Planet.b]
  print(WithM.y.tag); // expect: 1-y
  print(G.i.make().runtimeType); // expect: List<int>
  print(G.one()); // expect: G.i
  print(G.s is G<String>); // expect: true
  print(G.values.runtimeType); // expect: List<G<dynamic>>
  print(Holder(Level.values).next(Level.high)); // expect: Level.low
  Impl().test();
  // expect: 8
  // expect: 12
  // expect: 8
  Base b = Impl();
  print(b.vv); // expect: 8
  b.run();
  // expect: 12
  // expect: 8
  Impl()
    ..run()
    ..v = 9
    ..run();
  // expect: 12
  // expect: 8
  // expect: 27
  // expect: 18
  a
    ?..sq
    ..abs();
  z?..length;
  final List<num> ns = <int>[4];
  print(ns.total); // expect: 4
  print(Level.low.hashCode == Level.low.hashCode); // expect: true
  print({Level.low, Level.high, Level.low}.length); // expect: 2
  print(identical(const [Level.low], const [Level.low])); // expect: true
  var sum = 0;
  for (final l in Level.values) {
    sum += switch (l) {
      Level.low => 1,
      Level.high => 2,
    };
  }
  print(sum); // expect: 3
  Object o = Level.low;
  print(switch (o) {
    Level.low => 'low',
    Level.high => 'high',
    _ => '?',
  }); // expect: low
  print(Level.values.map((e) => e.name).join(',')); // expect: low,high
  dynamic d = Level.high;
  print(d.n); // expect: 10
  try {
    d.foo();
  } catch (e) {
    print('$e'.split('\n').first);
  }
  // expect: NoSuchMethodError: Class 'Level' has no instance method 'foo'.
  print(d.toString()); // expect: Level.high
  print(Enum.compareByIndex(Level.low, Level.high)); // expect: -1
  print(Level.values.asMap()); // expect: {0: Level.low, 1: Level.high}
  print(Level.high.toString().length); // expect: 10
}
