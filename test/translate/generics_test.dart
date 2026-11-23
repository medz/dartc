import 'package:test/test.dart';

import '../support/new_compiler.dart';
import 'support.dart';

const _tools = r'''
void show(Object? o) {
  if (o == null) { print('null'); }
  else if (o is int) { number(o); }
  else if (o is bool) { truth(o); }
  else if (o is double) { print('double'); number((o * 2).toInt()); }
  else if (o is A) { print('A'); number(o.n); }
  else { print('other'); }
}
class A { final int n; const A(this.n); }
class B extends A { const B(super.n); }
class Box<T> { T value; Box(this.value); T get() => value; void set(T v) { value = v; } Box<T> copy() => Box(value); Box<S> map<S>(S Function(T) f) => Box(f(value)); bool holds(Object? o) => o is T; T cast(Object? o) => o as T; }
class Pair<X, Y> { final X first; final Y second; const Pair(this.first, this.second); Pair<Y, X> swap() => Pair(second, first); }
class Node<T> { final T item; final Node<T>? next; const Node(this.item, [this.next]); void each(void Function(T) f) { Node<T>? at = this; while (at != null) { f(at.item); at = at.next; } } R fold<R>(R start, R Function(R, T) f) { var r = start; each((t) => r = f(r, t)); return r; } }
T same<T>(T t) => t;
R call<T, R>(R Function(T) f, T t) => f(t);
int twice(int n) => n * 2;
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_tools\n$source');

  group('generic classes', () {
    shows('hold values of any type', '''
      void main() {
        final i = Box(5); number(i.value + 1); i.value = 7; number(i.get()); i.set(i.value * 2); number(i.copy().value); i.value += 3; number(i.value++); number(i.value);
        final d = Box(1.5), b = Box(true), a = Box(A(4)), n = Box<int?>(null), o = Box<Object?>(3), m = Box<num>(2); truth(d.value > 1); if (b.value) print('yes'); number(a.value.n); show(n.value); n.value = 6; show(n.value); o.value = A(1); show(o.value); m.value += 0.5; show(m.value);
        final p = Pair(1, A(2)); number(p.first); number(p.second.n); final q = p.swap(); number(q.first.n); number(q.second); number(Pair<int, double>(1, 2).first); truth(Pair<int, double>(1, 2).second == 2.0);
        final nested = Box(Box(Pair(3, 4.5))); number(nested.value.value.first); nested.value.value = Pair(8, 0); number(nested.value.value.first); d.value = 3; truth(d.value / 2 == 1.5); Box<double> e = Box(4); truth(e.value / 8 == 0.5);
        final list = Node(1, Node(2, Node(3))); list.each(number); number(list.fold(0, (s, t) => s + t)); truth(list.fold(true, (s, t) => s && t > 0)); show(list.fold<num>(0.5, (s, t) => s + t)); number(i.map((v) => v > 1 ? 1 : 2).value); number(i.map(twice).map((v) => A(v)).value.n);
      }
    ''');
    shows('extend and implement each other', '''
      abstract class Get<T> { T get(); int size() => 1; } abstract class Put<T> { void put(T t); }
      class Cell<T> implements Get<T>, Put<T> { T t; Cell(this.t); @override T get() => t; @override void put(T x) { t = x; } @override int size() => 2; }
      class IntCell extends Cell<int> { IntCell(super.t); @override int get() => super.get() + 1; int twice() => t * 2; }
      class Same<T> extends Cell<Pair<T, T>> { Same(T a) : super(Pair(a, a)); T left() => t.first; }
      class Opt<T> extends Get<T?> { @override T? get() => null; }
      T take<T>(Get<T> g) => g.get();
      void main() { final c = Cell(3); c.put(4); number(c.get()); number(take(c)); Get<int> g = IntCell(5); number(g.get()); number(g.size()); number(IntCell(6).twice()); Cell<int> k = IntCell(7); k.t = 9; number(k.get()); k.put(1); number(k.t); final s = Same(A(8)); number(s.left().n); number(s.get().second.n); show(Opt<int>().get()); number(Opt<A>().size()); Put<int> p = c; p.put(20); number(c.t); num z = take<num>(c); show(z); }
    ''');
    shows(
      'have constructors and statics',
      '''
      class C<T> { final T a; T? b; final int k; static int made = 0; static T id<T>(T t) => t; C(this.a, {this.b, this.k = 3}) { made++; } C.twice(T t) : this(t, b: t); C.init(T t) : a = t, b = null, k = 1; factory C.of(T t) => C(t, k: 9); factory C.sub(T t) = D<T>; Box<T> box() => Box<T>(a); List2<T> list() => List2(); }
      class D<T> extends C<T> { D(T t) : super(t, k: 5); D.named(super.a, {super.b, super.k}) : super(); } class List2<T> { bool ok(Object? o) => o is T; }
      void main() { number(C(1).a); number(C(2, b: 4, k: 7).k); show(C(2, b: 4).b); show(C.twice(6).b); number(C.init(A(3)).a.n); number(C.of(5).k); number(D(8).k); show(D.named(1.5, k: 2).a); show(D.named(1, b: 2).b); number(C.made); number(C.id(11)); truth(C.of(5).box().holds(1)); truth(C.of(5).box().holds(1.5)); truth(D(A(1)).list().ok(B(2))); truth(D<B>(B(1)).list().ok(A(2))); C<num> c = C.of(3); truth(c.box().holds(1.5)); }
    '''
          .replaceAll(' factory C.sub(T t) = D<T>;', ''),
    );
    shows('with bounds', '''
      abstract class Shape { int area(); } class Sq extends Shape { final int s; Sq(this.s); @override int area() => s * s; }
      class Max<T extends num> { T a; Max(this.a); num plus(T b) => a + b; bool less(T b) => a < b; T get() => a; double half() => a / 2; int whole() => a.toInt(); }
      class Holder<T extends Shape> { final T t; Holder(this.t); int twice() => t.area() * 2; bool eq(T o) => t == o; } int area<T extends Shape>(T t) => t.area(); T biggest<T extends Shape>(T a, T b) => a.area() > b.area() ? a : b;
      T next<T extends Object>(T? t, T d) => t ?? d; bool flag<T extends bool>(T t) => t ? true : false; num sum<T extends num>(T a, T b) { num r = a; r += b; return r; }
      void main() { final m = Max(3); show(m.plus(4)); truth(m.less(9)); number(m.get() + 1); truth(m.half() == 1.5); number(Max(2.5).whole()); show(Max<num>(1).plus(0.5)); number(Holder(Sq(3)).twice()); final s = Sq(2); truth(Holder(s).eq(s)); number(area(Sq(5))); number(biggest(Sq(1), Sq(6)).s); number(next(null, 4)); number(next(5, 4)); truth(flag(true)); show(sum(1, 2)); show(sum(1.5, 2.5)); }
    ''');
    shows('know their types', '''
      void t(Object? o) { truth(o is Box); truth(o is Box<int>); truth(o is Box<num>); truth(o is Box<Object>); truth(o is Box<int?>); truth(o is Box<Box<int>>); truth(o is Pair<int, num>); truth(o is Box<dynamic>); truth(o is Box<A>?); truth(o is Sub); truth(o is Get<num>); truth(o is Get<Get<int>>); print('-'); }
      abstract class Get<T> {} class Sub extends Box<int> implements Get<double> { Sub() : super(1); } class Deep<T> extends Pair<T, Box<T>> implements Get<Get<T>> { Deep(T t) : super(t, Box(t)); }
      void main() { t(Box(1)); t(Box(1.5)); t(Box<num>(1)); t(Box<int?>(1)); t(Box(Box(1))); t(Box<Object?>(1)); t(Box<dynamic>(1)); t(Pair(1, 2)); t(Pair(1, 2.5)); t(Sub()); t(Deep(1)); t(Deep<num>(1)); t(null); t(Box<A>(B(1))); t(Box<B>(B(1))); t(Box(null)); t(1);
        Object o = Box(5); if (o is Box<int>) number(o.value + 1); number((o as Box<num>).value.toInt()); try { o as Box<double>; } on TypeError { print('T'); } Object? p = Deep(4); if (p is Pair<int, Box<int>>) number(p.second.value); }
    ''');
    shows(
      'check what they are given',
      '''
      class Put<T> { T? t; void put(T v) { t = v; } void both(T a, [T? b]) { t = b ?? a; } void named({required T a}) { t = a; } T operator [](T i) => i; void operator []=(T i, T v) { t = v; } void all(Box<T> b) { t = b.value; } void fn(void Function(T) f) => f(t as T); void fr(T Function() f) { t = f(); } set s(T v) { t = v; } bool operator <(T o) => true; }
      class IntPut extends Put<int> { @override void put(int v) { t = v + 1; } }
      void go(void Function() f) { try { f(); print('ok'); } on TypeError { print('T'); } }
      void main() { Put<num> p = Put<int>(); go(() => p.put(1)); go(() => p.put(1.5)); go(() => p.both(1, 2.5)); go(() => p.both(2)); go(() => p.named(a: 0.5)); go(() => p[0.5]); go(() => p[1] = 1.5); go(() => p[1] = 2); go(() => p.t = 1.5); go(() => p.t = 3); go(() => p.all(Box(1.5))); go(() => p.all(Box<int>(4))); go(() => p.all(Box<num>(4))); go(() => p.s = 7.5); go(() => p.s = 7); go(() => p < 1.5); go(() => p < 1); go(() => p.fn((n) => show(n))); go(() => p.fr(() => 1.5)); go(() => p.fr(() => 8)); show(p.t); Put<num> q = IntPut(); go(() => q.put(1.5)); go(() => q.put(5)); show(q.t); Put<Object?> r = p; go(() => r.put(null)); go(() => r.put('a' == 'a')); dynamic d = 1; go(() => r.put(d)); }
    '''
          .replaceAll("'a' == 'a'", 'true'),
    );
    shows(
      'check functions they give',
      '''
      class F<T> { void Function(T) f; F(this.f); void Function(T) get g => f; void Function(T) m() => f; T Function() r(T t) => () => t; }
      void go(void Function() f) { try { f(); print('ok'); } on TypeError { print('T'); } }
      void main() { F<num> f = F<int>((n) => number(n)); go(() => f.f(1)); go(() => f.f); go(() { final g = f.g; g(1); }); go(() => f.m()(2)); go(() => show(f.r(3)())); F<int> k = F<int>((n) => number(n)); go(() => k.f(5)); go(() => k.g(6)); F<int> w = F<num>((n) => show(n)); }
    '''
          .replaceAll(' F<int> w = F<num>((n) => show(n));', ''),
    );
    shows('give methods that check what they are given', '''
      class P<T> { void put(T t) { show(t); } void f(void Function(T) g) {} T id(T t) => t; void c(covariant num n) { show(n); } void two([T? a]) { show(a); } void named({required T a, int b = 1}) { show(a); number(b); } }
      class Q extends P<int> { @override void put(int t) { show(t); } @override void named({required int a, int b = 2}) { number(a + b); } }
      void t(Object o) { truth(o is void Function(Object?)); truth(o is void Function(Null)); truth(o is void Function(int)); truth(o is void Function(void Function(int))); truth(o is void Function({required num a, int b})); print('-'); }
      void go(void Function() f) { try { f(); print('ok'); } on TypeError { print('T'); } }
      void main() { t(P<int>().put); t(P<int>().f); t(P<int>().id); t(P<int>().c); t(P<int>().two); t(Q().put); t(Q().named); P<num> p = P<int>(); final f = p.put; go(() => f(1.5)); go(() => f(2)); final Object g = p.c; go(() => (g as void Function(Object?))(true)); go(() => (g as void Function(Object?))(3)); P<num> q = Q(); go(() => (q.put)(1.5)); go(() => (q.put)(4)); go(() => (q.two)(2.5)); go(() => (q.two)()); final n = q.named; go(() => n(a: 1.5)); go(() => n(a: 5, b: 6)); go(() => show(p.id(7))); go(() => show((p.id)(8.5))); }
    ''');
    shows(
      'are constant',
      '''
      const p = Pair(1, A(2)); const q = Pair<num, A>(1, B(2)); const Node<int> n = Node(1, Node(2)); class K<T> { final Pair<T, T> p; const K(T a) : p = const Pair<Never, Never>(throw0, throw0); static const throw0 = 1 > 2 ? 1 : 2; }
      Object? def([Object? o = const Box2<int>(5)]) => o; class Box2<T> { final T t; const Box2(this.t); bool holds(Object? o) => o is T; }
      void main() { number(p.first); number(p.second.n); truth(identical(p, const Pair(1, A(2)))); truth(identical(const Pair<num, A>(1, A(2)), p)); truth(const Pair(1, A(2)) is Pair<int, A>); truth(q is Pair<int, A>); n.each(number); truth(def() is Box2<int>); truth(const Box2<int>(1).holds(2)); truth(const Box2<num>(1).holds(2.5)); truth(const Box2(1).holds(2.5)); truth(identical(const Box2<int>(1), const Box2<num>(1))); }
    '''
          .replaceAll(
            'class K<T> { final Pair<T, T> p; const K(T a) : p = const Pair<Never, Never>(throw0, throw0); static const throw0 = 1 > 2 ? 1 : 2; }',
            '',
          ),
    );
  });

  group('generic functions', () {
    shows(
      'take and give values',
      '''
      (int, int)? none; 
    '''
          .replaceAll('(int, int)? none;', '''
      T? orNull<T>(bool b, T t) => b ? t : null; bool isA<T>(Object? o) => o is T; T to<T>(Object? o) => o as T; Pair<X, Y> pair<X, Y>(X x, {required Y y}) => Pair(x, y); Box<T> box<T>(T t) => Box<T>(t); int count<T>(Object? a, Object? b) => (a is T ? 1 : 0) + (b is T ? 1 : 0); T pick<T>(int n, T a, [T? b]) => n > 0 ? a : b ?? a; void each<T>(T a, T b, void Function(T) f) { f(a); f(b); } bool inner<T>(Object? o) => isA<Box<T>>(o); bool opt<T>(Object? o) => isA<T?>(o);
      void main() { number(same(4) + 1); truth(same(1.5) > 1); show(same(null)); number(same(A(3)).n); show(orNull(false, 5)); show(orNull(true, 5)); truth(isA<int>(1)); truth(isA<int>(1.5)); truth(isA<int?>(null)); truth(isA<A>(B(1))); truth(isA<Box<num>>(Box(1))); number(to<int>(6) + 1); try { to<A>(1); } on TypeError { print('T'); } number(pair(1, y: A(2)).second.n); truth(box(1) is Box<int>); truth(box<num>(1) is Box<int>); number(count<num>(1, A(1))); number(count<Object>(1, null)); number(pick(0, 1, 2)); number(pick(0, 7)); each(1, 2, number); each<num>(1, 2.5, show); truth(inner<int>(Box(1))); truth(inner<double>(Box(1))); truth(opt<int>(null)); truth(opt<int>(1.5)); number(call(twice, 5)); number(call((A a) => a.n, A(6))); truth(call<int, num>(twice, 4) is int); final s = same<int>(9); number(s); }
    '''),
    );
    shows('are methods', '''
      class M<T> { final T t; M(this.t); R conv<R>(R Function(T) f) => f(t); Pair<T, S> with2<S>(S s) => Pair(t, s); bool test<S>(Object? o) => o is Pair<T, S>; S plain<S>(S s) => s; static S st<S>(S s) => s; }
      class N extends M<int> { N() : super(4); @override R conv<R>(R Function(int) f) => f(t + 100); @override S plain<S>(S s) { print('N'); return super.plain<S>(s); } }
      void main() { final m = M(3); number(m.conv((n) => n * 2)); truth(m.conv((n) => n > 2)); number(m.with2(A(5)).second.n); truth(m.with2(1.5) is Pair<int, double>); truth(m.test<int>(Pair(1, 2))); truth(m.test<int>(Pair(1, 2.5))); M<int> n = N(); number(n.conv((k) => k)); number(n.plain(8)); number(M.st(9)); number(n.plain<int>(1)); M<num> w = n; show(w.conv<Object>((k) => k + 0.5)); }
    ''');
    shows('are local, and closures see types', '''
      Object? make<T>(T t) { Box<T> b() => Box<T>(t); S id<S>(S s) => s; bool both<S>(Object? o) => o is Pair<T, S>; final f = (Object? o) => o is T; truth(f(1)); truth(f(1.5)); truth(both<int>(Pair<T, int>(t, 1))); show(id(t)); return () => b(); }
      class G<T> { bool Function(Object?) tester() => (o) => o is T; Box<S> Function(S) maker<S>() => (s) => Box<S>(s); T Function(T) idf() { T go(T t) => t; return go; } }
      void main() { final f = make(1); truth(f is Object? Function()); truth(f is Box<int> Function()); truth(f is Box<double> Function()); final g = make<num>(1); truth(g is Box<int> Function()); truth((g as Box<num> Function())() is Box<num>); truth(G<int>().tester()(1)); truth(G<int>().tester()(1.5)); truth(G<int>().maker<A>()(A(1)) is Box<A>); truth(G<int>().idf() is int Function(int)); truth(G<int>().idf() is num Function(int)); truth(G<int>().idf() is int Function(Object)); number(G<int>().idf()(7)); }
    ''');
    shows('are values once their types are known', '''
      int Function(int) f = same; num Function(num) g = same<num>; class S { static T st<T>(T t) => t; } R app<R>(R Function(int) h) => h(4); const int Function(int) c = same; Box<int> Function(int) mk = Box.new; final mk2 = Box<num>.new; Pair<A, B> Function(A, B) pr = Pair.new;
      void main() { number(f(3)); show(g(1.5)); int Function(int) h = S.st; number(h(5)); truth(identical(c, f)); truth(f == same<int>); truth(g == f); number(app(same)); number(call(same, 6)); truth(f is int Function(int)); truth(f is num Function(num)); truth(g is num Function(num)); number(mk(8).value); truth(mk(8) is Box<int>); truth(mk2(8) is Box<int>); truth(mk2(8) is Box<num>); number(pr(A(1), B(2)).second.n); final q = same<A>; number(q(A(9)).n); }
    ''');
    shows('are tested by their bounds and catches', '''
      class E<T> implements Exception { final T t; E(this.t); } void thrower<T>(T t) => throw E<T>(t); void tryIt<T>(void Function() f) { try { f(); } on E<T> catch (e) { print('T'); show(e.t); } on E<num> { print('num'); } on E catch (e) { print('E'); show(e.t); } }
      void main() { tryIt<int>(() => thrower(1)); tryIt<int>(() => thrower(1.5)); tryIt<int>(() => thrower(A(2))); tryIt<Object>(() => thrower(A(2))); tryIt<double>(() => thrower<num>(1.5)); }
    ''');
    shows('know functions', '''
      bool one<T>() => 1 is T; bool yes() => one<int>(); void named({int? a}) {} void other({int? b}) {} class L<T> { List2<T> all() => List2<T>(); } class List2<T> extends Pair<T?, T Function(int)> { List2() : super(null, (t) => throw t); }
      void main() { truth(one<int>()); truth(one<num>()); truth(one<double>()); Object a = yes(), b = yes(); truth(identical(a, b)); truth(a == b);
        Object o = Box<void Function()>(() {}); truth(o is Box<Function>); truth(o is Box<int Function()>); truth(o is Box<void Function([int])>); Object n = named; truth(n is void Function({int a})); truth(n is void Function({int b})); truth(n is void Function()); n = other; truth(n is void Function({int b})); Object p = L<int>().all(); truth(p is Pair<num?, num Function(int)>); truth(p is Pair<int?, int Function(int)>); truth(p is Pair<int, int Function(int)>); }
    ''');
    shows('promote', '''
      num add<T>(T t) { if (t is int) return t + 1; if (t is num) return t * 2; return -1; } T inc<T extends num>(T t) { if (t is int) { final int k = t; number(k + 1); } return t; } int len<T>(T? t) { if (t == null) return 0; if (t is A) return t.n; return 1; }
      void main() { show(add(1)); show(add(1.5)); show(add(A(1))); number(inc(4)); show(inc(1.5)); number(len<A>(null)); number(len(B(6))); number(len(1)); }
    ''');
  });

  for (final (name, body) in [
    ('a generic cast', 'Object o = Box(1); o as Box<double>;'),
    ('a cast to a parameter', 'Box<int>(1).cast(A(1));'),
    (
      'a nested one',
      'Object o = Pair(1, Box(A(2))); o as Pair<int, Box<int>>;',
    ),
    ('an argument', 'Box<num> b = Box<int>(1); b.set(1.5);'),
    ('a field', 'Box<Object?> b = Box<A>(A(1)); b.value = null;'),
    ('a function', 'Object o = same<int>; o as int Function(num);'),
    ('an object', 'throw Pair<int, Box<A?>>(1, Box(null));'),
    ('a nullable type', 'Box<int?>(1).cast(2.5);'),
    (
      'optional parameters',
      'Object o = (int a, [bool? b, A? c]) => 1; o as Box<int>;',
    ),
    (
      'named parameters',
      'Object o = ({required int b, A? a}) {}; o as Box<int>;',
    ),
    (
      'both kinds',
      'Object o = (int a, {bool? b}) => a; o as int Function({int b});',
    ),
    (
      'a nullable function',
      'Object o = Box<void Function(int)?>(null); o as Box<dynamic Function()>;',
    ),
    ('void and dynamic', 'Object o = Pair<dynamic, void>(1, 2); o as int;'),
  ]) {
    shows('end the program: $name', "void main() { print('a'); $body }");
  }

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(translate(source), failsWith(['main.dart:$problem']));
    });

    const what = 'Not supported yet:';
    reports(
      'T f<T>(T t) => t;\nvoid main() { final g = f; }',
      '2:21: $what a variable of type T Function<T>(T).',
    );
    reports(
      'void main() { final g = <T>(T t) => t; }',
      '1:21: $what a variable of type T Function<T>(T).',
    );
    reports(
      'class A { S f<S>(S s) => s; }\nvoid main() { int Function(int) g = A().f; }',
      '2:37: $what tear-offs of generic methods.',
    );
  });
}
