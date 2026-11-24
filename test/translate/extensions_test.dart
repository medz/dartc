import 'package:test/test.dart';

import 'support.dart';

void main() {
  agrees('members of extensions', r'''
extension Numbers on int {
  static int made = 0;
  static int make(int n) { made++; return n * 2; }
  int get doubled => this * 2;
  int plus(int other, {int times = 1}) => this + other * times;
  int operator [](int i) => (this >> i) & 1;
  bool get isBig { bool check() => this > 100; return check(); }
  set note(int n) { print('$this notes $n'); }
  int again() => plus(1) + doubled + abs();
}
extension on double {
  double half() => this / 2;
}
extension Texts on String? {
  String orElse(String other) => this ?? other;
  bool get isMissing => this == null;
}
extension Anything on Object? {
  String get shown => '<$this>';
}
void main() {
  print(3.doubled);
  print(3.plus(4));
  print(3.plus(4, times: 5));
  print(6[1]); print(6[0]);
  print(200.isBig); print(2.isBig);
  5.note = 9;
  var n = 4;
  n.note = 1;
  print(4.again());
  print(Numbers.make(21)); print(Numbers.made);
  print(3.5.half());
  String? none = DateTime.now().year < 3 ? 'x' : null;
  print(none.orElse('other')); print(none.isMissing);
  print('a'.orElse('b')); print(none?.shown); print(none.shown);
  print(3.shown); print(null.shown); print([1].shown);
  print(Numbers(7).doubled);
  print(Numbers(7)[0]);
  print(Texts(none).orElse('z'));
  int? some = n, missing = none?.length;
  print(some?.doubled); print(missing?.doubled);
  print(some?.plus(2, times: 3)); print(missing?.plus(2));
  missing?.note = 4;
}
''');

  agrees('generic extensions', r'''
extension Lists<T> on List<T> {
  T get middle => this[length ~/ 2];
  List<R> both<R>(R Function(T value) make) => [for (final e in this) make(e)];
  Type get type => T;
  bool holds(Object? value) => value is T;
  List<T> copy() => [...this];
  void twice() { add(first); add(this.last); }
  Map<T, R> paired<R>(R value) => {for (final e in this) e: value};
  Type Function() get later => () => T;
  Type pair<R>() => Map<T, R>;
}
extension Compare<T extends Comparable<T>> on T {
  T orMore(T other) => compareTo(other) < 0 ? other : this;
}
extension Run<T> on T {
  R let<R>(R Function(T it) work) => work(this);
  T also(void Function(T it) work) { work(this); return this; }
}
extension Compose<A, B> on B Function(A) {
  C Function(A) then<C>(C Function(B) next) => (a) => next(this(a));
}
class Box<T> {
  final T value;
  Box(this.value);
  Type inner() => [value].type;
  String show() => describe('!');
}
extension on Box<num> { String describe(String end) => 'box of $value$end'; }
extension BoxOf<T> on Box<T> { String describe(String end) => 'some $value$end'; }
void main() {
  final list = [1, 2, 3];
  print(list.middle); print(list.type); print(list.holds('x')); print(list.holds(1));
  print(list.both((n) => '$n!'));
  print(list.copy().runtimeType);
  print((list..twice()));
  print(['a'].paired(2.5).runtimeType);
  print(<num>[1, 2].later());
  print(['x'].pair<bool>());
  print('a'.orMore('b'));
  print(3.let((it) => it + 1)); print('q'.let((it) => it.length));
  final half = ((int n) => n / 2).then((d) => 'it is $d');
  print(half(5));
  print(Box(3).inner()); print(Box('s').show()); print(Box(2).show());
  print(Lists<Object>(list).type);
  final tear = list.both;
  print(tear<int>((n) => n * n));
  print(Run(8).also((it) => print('also $it')));
  List<Object> other = <String>['s'];
  print(other.type); print(other.holds(3));
}
''');

  agrees('extension operators and calls', r'''
class Point {
  int x, y;
  Point(this.x, this.y);
  String toString() => '($x, $y)';
}
extension on Point {
  Point operator +(Point other) => Point(x + other.x, y + other.y);
  Point operator -() => Point(-x, -y);
  bool operator <(Point other) => x < other.x;
  int operator [](int i) => i == 0 ? x : y;
  void operator []=(int i, int value) { if (i == 0) { x = value; } else { y = value; } }
  Point call(int by) => Point(x * by, y * by);
  int get sum => x + y;
  set sum(int value) => x = value - y;
}
extension Next on int {
  int operator ~() => this + 1000;
  Iterable<int> upTo(int end) => [for (var i = this; i <= end; i++) i];
}
void main() {
  var p = Point(1, 2);
  print(p + Point(3, 4)); print(-p); print(p < Point(2, 0));
  p += Point(10, 10); print(p);
  print(p[0]); p[1] = 5; print(p); p[0] += 3; print(p); print(p[1]++); print(p);
  p.sum = 50; print(p); p.sum += 4; print(p); print(p.sum++); print(p.sum);
  print(p(2)); print(p.call(3));
  Point Function(int) f = p.call; print(f(1));
 
  for (final i in 3.upTo(5)) print(i);
  Point? none = p.x < 0 ? p : null;
  print(none?[0]); none?[0] = 2; print(none?.sum); none?.sum += 1;
  print((none ?? p).sum);
  void Function() late = () => print(p.sum);
  p.x = 0; late();
}
''');

  agrees('tear-offs of extension methods', r'''
extension Numbers on int {
  int plus(int other) => this + other;
  T same<T>(T value) => value;
}
extension Lists<T> on List<T> { bool holds(Object? value) => value is T; }
void main() {
  final add = 3.plus;
  print(add(4)); print(add.runtimeType);
  print([1, 2].map(10.plus).toList());
  String Function(String) same = 3.same;
  print(same('s')); print(3.same<int>(5));
  final holds = ['a'].holds;
  print(holds('a')); print(holds(1)); print(holds.runtimeType);
  print(Numbers(3).plus(9));
  dynamic d = add; print(d(1));
  try { d('x'); } catch (e) { print(e); }
}
''');

  agrees('members that extensions of the SDK declare', r'''
void main() {
  print(<int>[].firstOrNull); print([3].firstOrNull); print([1, 2].lastOrNull);
  print([1, null, 2].nonNulls.toList());
  
  print([1, 2].elementAtOrNull(5));
  Iterable<int> one = [4]; print(one.singleOrNull);
}
''');

  agrees('with enums and other types', r'''
enum Level { low(1), high(10); final int n; const Level(this.n); static const all = [low, high]; static const map = {low: 'l', high: 'h'}; }
class Conf { final Level level; final List<Level> more; const Conf(this.level, [this.more = const [Level.low]]); }
const conf = Conf(Level.high);
extension LevelX on Level { Level get other => this == Level.low ? Level.high : Level.low; static Level parse(String s) => Level.values.firstWhere((l) => l.name == s); }
extension OnFn on void Function(int) { void twice(int n) { this(n); this(n + 1); } void callAll(List<int> l) => l.forEach(this); }
extension on num { num get sq => this * this; Comparable<num> get c => this; }
extension Nums<T extends num> on Iterable<T> { num get total => fold<num>(0, (a, b) => a + b); T get biggest => reduce((a, b) => m.max(a, b)); }
extension Opt<T extends Object> on T? { R? map<R>(R Function(T) f) { final self = this; return self == null ? null : f(self); } T get must => this!; }
extension Phantom on bool { int get asInt => this ? 1 : 0; bool operator [](bool o) => this && o; }
sealed class S { }
enum Planet implements Comparable<Planet> { a, b; @override int compareTo(Planet o) => index.compareTo(o.index); bool operator <(Planet o) => compareTo(o) < 0; }
mixin M on Enum { String get tag => '${index}-$name'; }
enum WithM with M { x, y }
enum G<T> { i<int>(), s<String>(); const G(); List<T> make() => <T>[]; static G<int> one() => i; }
class Holder<E extends Enum> { final List<E> values; Holder(this.values); E next(E e) => values[(e.index + 1) % values.length]; }
abstract class Base { int get v; }
extension BaseX on Base { int get vv => v * 2; void run() { void inner() { print(vv + v); print(this.vv); } inner(); } }
class Impl extends Base { int v = 4; void test() { print(vv); run(); } }
void main() {
  print(conf.level.n); print(conf.more); print(Level.all); print(Level.map); print(conf.level.other); print(LevelX.parse('low'));
  final f = LevelX.parse; print(f('high'));
  ((int n) => print('n$n')).twice(3); void g(int n) => print('g$n'); g.twice(7); g.callAll([1,2]); (print as void Function(int)).twice(0);
  print(3.sq); print(2.5.sq); num q = 4; print(q.sq); print(q.c.compareTo(3));
  print([1,2,3].total); print([1.5,2].total); print([1,5,2].biggest); print(<double>[1,0].biggest);
  int? a = conf.level.n > 100 ? null : 5; print(a.map((x) => x + 1)); String? z = conf.level.n > 1 ? null : ''; print(z.map((s) => s.length));
  try { z.must; } catch (e) { print(e); } print(a.must);
  print(true.asInt); print(true[false]);
  print(Planet.a < Planet.b); print([Planet.b, Planet.a]..sort()); print(WithM.y.tag);
  print(G.i.make().runtimeType); print(G.one()); print(G.s is G<String>); print(G.values.runtimeType);
  print(Holder(Level.values).next(Level.high)); Impl().test(); Base b = Impl(); print(b.vv); b.run();
  Impl()..run()..v = 9..run();
  a?..sq..abs(); z?..length;
  final List<num> ns = <int>[4]; print(ns.total);
  print(Level.low.hashCode == Level.low.hashCode); print({Level.low, Level.high, Level.low}.length); print(identical(const [Level.low], const [Level.low]));
  var sum = 0; for (final l in Level.values) { sum += switch (l) { Level.low => 1, Level.high => 2 }; } print(sum);
  Object o = Level.low; print(switch (o) { Level.low => 'low', Level.high => 'high', _ => '?' });
  print(Level.values.map((e) => e.name).join(',')); dynamic d = Level.high; print(d.n); try { d.foo(); } catch (e) { print('$e'.split('\n').first); } print(d.toString());
  print(Enum.compareByIndex(Level.low, Level.high)); print(Level.values.asMap()); print(Level.high.toString().length);
}
''', imports: "import 'dart:math' as m;");

  group('extension types', () {
    agrees('members and constructors', r'''
extension type Id(int value) {
  Id.of(String text) : this(int.parse(text));
  Id.double(int n) : value = n * 2;
  factory Id.zero() => Id(0);
  static int made = 3;
  static Id next() => Id(made++);
  Id operator +(Id other) => Id(value + other.value);
  bool get isEven => value.isEven;
  String show([String end = '!']) => 'Id($value)$end';
}
extension type const Name._(String text) implements String {
  const Name(String text) : this._(text);
  String get loud => toUpperCase() + '!';
  int get length => 99;
}
extension type Numbers(List<int> _) implements Iterable<int> {
  void push(int n) => _.add(n);
  int operator [](int i) => _[i];
}
const name = Name('cat');
void main() {
  final id = Id(3);
  print(id.value); print(id.show()); print((id + Id.of('4')).show('?'));
  print(Id.double(5).value); print(Id.zero().value); print(Id.next().value);
  print(Id.next().value); print(id.isEven);
  Object o = id as Object; print(o is int); print(o is Id); print(id == 3); print(id.runtimeType);
  print(<Id>[id].runtimeType); print(o as Id);
  print(name); print(name.loud); print(name.length); print(name.substring(1));
  String plain = name; print(plain.length);
  final numbers = Numbers([1, 2]); numbers.push(7);
  print(numbers[2]); print(numbers.length); print(numbers.map((n) => n + 1).toList());
  for (final n in numbers) print(n);
  Id? none = o is String ? id : null; print(none?.value); print(none == null);
  final make = Id.new; print(make(6).value);
  final show = id.show; print(show('.'));
  Map<Id, int> map = {id: 1}; print(map[Id(3)]);
}
''');

    agrees('generic ones and those on others', r'''
extension type Wrap<T>(T inner) {
  Type get type => T;
  Wrap<R> map<R>(R Function(T) f) => Wrap(f(inner));
  bool fits(Object? o) => o is T;
  T get get => inner;
}
extension type More<T>(Wrap<T> it) implements Wrap<T> {
  T get again => it.inner;
}
extension type Positive._(int n) {
  Positive(this.n) { if (n < 0) throw ArgumentError('negative'); }
}
extension type Maybe<T>(T? value) {
  T or(T other) => value ?? other;
}
extension type Act(void Function(int) f) { void run() => f(4); }
extension Shown on Positive { String get shown => '+$n'; }
void main() {
  final w = Wrap(3);
  print(w.type); print(w.map((n) => 'v$n').inner); print(w.fits('x'));
  print(w.map((n) => 'v').type);
  final m = More(w); print(m.again); print(m.get); print(m.type);
  print(Positive(4).shown);
  try { Positive(-1); } catch (e) { print(e); }
  print(Maybe<int>(null).or(5)); print(Maybe(2).or(5));
  Act((n) => print(n)).run();
  dynamic d = w; print(d + 1);
  print(Wrap<num>(1).type); print((Wrap<List<int>>([1])).inner.first);
  List<Wrap<int>> list = [w, Wrap(9)]; print(list.map((e) => e.inner).toList());
  print(list.runtimeType);
}
''');
  });
}
