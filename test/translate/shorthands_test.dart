import 'support.dart';

void main() {
  agrees('primary constructors', r'''
int trace(int n) { print('t$n'); return n; }
class Point(final int x, var int y) { int get sum => x + y; String toString() => '($x, $y)'; }
class const Fixed(final int n, {final String name = 'none'});
class Empty();
class Base(final int a) { Base.twice(int n) : this(n * 2); }
class Sub(int a, final int b) extends Base { this : super(a + 1); final int c = a * 10; late final int d = c + b; }
class Super(super.a, {required final int k}) extends Base;
class Checked(final int n) { final int twice; this : assert(n > 0), twice = trace(n * 2) { print('body $n $twice'); count++; } static int count = 0; }
class Named.make(final String s, [int times = 2]) { final String all = s * times; factory Named(String s) => Named.make('<$s>'); }
class Generic<T>(final T value, final List<T> more) { Type get type => T; final int length = more.length; }
class Order(int p) { final int first = trace(p + 1); final int second = trace(p + 2); int third; this : third = trace(p + 3) { print('end $third'); } }
class Private({required this._x, int y = 1}) { final int _x; final int z = y + 1; }
class Over(final int x) implements Comparable<Over> { @override int compareTo(Over o) => x - o.x; }
abstract class Abs(final int v) { int get w; }
class Impl(super.v) extends Abs { int get w => v + 1; }
enum Size(final int n) { small(1), large(10); int get d => n * 2; }
enum Planet { a, b }
extension type Id(int n) { int get next => n + 1; }
extension type Pos(int n) { this { if (n < 0) throw ArgumentError('neg'); print('pos $n'); } }
mixin M { int get m => 5; }
class Mixed(final int q) with M;
class Closer(int n) { final int Function() get = () => n; void Function()? f; this { f = () => n + 10; } }
void main() {
  final p = Point(1, 2); p.y = 5; print(p); print(p.sum);
  print(const Fixed(3).name); print(identical(const Fixed(1), const Fixed(1))); print(Fixed(2, name: 'q').name); Empty();
  final s = Sub(1, 2); print('${s.a} ${s.b} ${s.c} ${s.d}'); print(Super(4, k: 9).a); print(Super(4, k: 9).k); print(Base.twice(4).a);
  final c = Checked(4); print(c.twice); print(Checked.count);
  print(Named('x').all); print(Named.make('y', 3).all);
  final g = Generic(1, [2, 3]); print(g.type); print(g.length);
  final o = Order(10); print(o.first + o.second); print(Private(x: 3)._x); print(Private(x: 3, y: 4).z);
  print((<Over>[Over(3), Over(1)]..sort()).first.x); print(Impl(3).w); print(Size.large.d); print(Size.values);
  print(Id(3).next); print(Pos(2).n); try { Pos(-1); } catch (e) { print(e); } print(Mixed(1).m);
  final cl = Closer(5); print(cl.get()); cl.f!();
  final make = Point.new; print(make(7, 8)); print(Generic<num>(1, []).type);
}
''');

  agrees('dot shorthands', r'''
enum Color { red, green; static Color pick(int n) => values[n]; static Color get best => green; static const fav = red; }
class Box { final int n; const Box(this.n); Box.twice(int k) : n = k * 2; factory Box.zero() => const .new(0); static Box max = Box(99); static Box of(int n) => Box(n); Box operator +(Box o) => Box(n + o.n); Box get next => Box(n + 1); Box add(int k) => .new(n + k); @override bool operator ==(Object o) => o is Box && o.n == n; @override int get hashCode => n; }
class G<T> { final T v; G(this.v); G.list(List<T> l) : v = l.first; static G<int> one() => G(1); }
extension type Meter(int m) { static Meter get zero => Meter(0); Meter.km(int k) : m = k * 1000; }
void take(Color c, {Box box = const .new(5)}) => print('$c ${box.n}');
Color get ret => .green;
Box make() { return .twice(4); }
void main() {
  Color c = .red; print(c); c = .green; print(c == .green); print(c != .red); Color d = .pick(0); print(d); d = .best; print(d); d = .fav; print(d);
  take(.red); take(.green, box: .new(7)); take(.red, box: .max); print(ret); print(make().n);
  Box b = .zero(); print(b.n); b = .of(3).next.add(4); print(b.n); Box e = Box(1) + .new(2); print(e.n); const Box k = .new(8); print(k.n); Box q = const .new(3); print(q.n);
  List<Color> l = [.red, .green, if (c == .green) .red]; print(l); Map<Color, Box> m = {.red: .new(1)}; print(m[Color.red]!.n);
  switch (c) { case .red: print('r'); case .green: print('g'); } print(switch (c) { .red => 1, .green => 2 });
  G<int> g = .new(4); print(g.v); G<String> h = .list(['a']); print(h.v); G<int> i = .one(); print(i.v);
  Meter z = .zero; print(z.m); z = .km(2); print(z.m); Color? n = c == .red ? null : .green; print(n); Object o = c; print(o == Color.green);
   Future<int>? fu; print(fu); int x = .parse('42'); print(x); double y = .infinity; print(y); Duration t = .zero; print(t); final s = <Duration>[.new(seconds: 2)]; print(s);
  if (o case Color.green) print('is'); print([Box(1), Box(2)].contains(const Box(2))); BigInt bi = .from(5); print(bi); String str = .fromCharCode(65); print(str);
}
''');

  agrees('other syntax', r'''
int top = 0; class H { static int s = 0; int f = 0; late int lf; }
int get g => top; set g(int v) => top = v * 2;
T id<T>(T x) => x;
class Call { T call<T>(T x, {int n = 1}) => x; }
class Nsm { noSuchMethod(i) => i.memberName; }
void main() {
  for (top in [1, 2]) print(top); for (g in [5]) print(top);
  top = 12;
  dynamic d; for (d in [1, 'a']) print(d); num n; for (n in <int>[1]) print(n + 1);
  final c = Call(); print(c('x')); print(c<int>(3, n: 2)); int Function(int) f = c.call; print(f(4)); int Function(int) f2 = c; print(f2(5));
  final List<Object? Function()> fs = [() => null, main2]; print(fs.length); print(id<int Function(int)>(id)(3));
  a: { if (top > 1) break a; print('no'); } 
  do { if (top++ > 14) continue; } while (top < 18); print(top);
  print([for (var i = 0; i < 3; i++) if (i.isOdd) i else ...[i, i]]); print({for (final e in {'a': 1}.entries) e.value: e.key}); int? q; print([?q, ?top]); print({'k': ?q});
  var (x, y) = (1, 2); x ^= 3; y <<= 2; x ??= 4; print('$x $y'); String s = 'a' 'b' "c"; print(s); print(r'\n$x'); print(0x1F + 1_000); print(1e3); print('\u{1F600}'.length); assert(() { print('never'); return true; }());
  var i = 0; i = i++ + ++i; print(i); print(i is! int); print(-5 ~/ 2); print(-5 % 3); print(5.remainder(-3)); print(7 >>> 1); final z = <int>[]..add(1)..addAll([2]); print(z);
  Object o = 3; if (o is int && o.isOdd) print('odd'); if (o is! String) print('ns'); print(o as num); col.Queue<int> qu = col.Queue()..add(3); print(qu.first);
  print((Nsm() as dynamic).foo); external1(); late String l; l = 'late'; print(l); print(const <String>{'a'}.contains('a')); print(#foo.bar); print(1.toString().codeUnits); covariantTest();
  switch (o) { case 1 || 2: print('small'); case int k when k > 2: print('k $k'); default: }
  void inner<T extends num>([T? a, int b = 2]) => print('$T $a $b'); inner<int>(1); inner(2.5, 3); inner();
  print(identical(id, id)); print(Call().runtimeType == Call); throwing();
}
Object? main2() => 1;
void external1() { try { throw 'x'; } on String catch (e) { print('s$e'); } on Object catch (e, t) { print(t); } finally { print('f'); } }
class A { void m(covariant num n) => print(n); } class B extends A { void m(int n) => print('B$n'); } void covariantTest() { A a = B(); try { a.m(1.5); } catch (e) { print(e); } a.m(1); }
Never fail(String s) => throw StateError(s); void throwing() { try { fail('q'); } on StateError catch (e) { print(e.message); } final int v = DateTime.now().year > 1 ? 1 : fail('z'); print(v); }
''', imports: "import 'dart:collection' as col;");
}
