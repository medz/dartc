import 'package:test/test.dart';

import 'support.dart';

const _tools = r'''
void show(Object? o) {
  if (o == null) { print('null'); }
  else if (o is int) { number(o); }
  else if (o is bool) { truth(o); }
  else if (o is double) { print('double'); number((o * 2).toInt()); }
  else { print('other'); }
}
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_tools\n$source');

  shows('add members', '''
    mixin M { int x = 3; int get twice => x * 2; void inc([int by = 1]) { x += by; } int abs1(); int use() => abs1() + twice; static int s = 5; static int st() => s++; }
    mixin N { int y = 10; int both() => y + 1; }
    class A with M { @override int abs1() => 100; } class B extends A with N { @override int both() => super.both() + x; } class C with M, N { @override int abs1() => y; }
    abstract class I { int both(); } class D = A with N implements I;
    void main() { final a = A(); a.inc(); number(a.x); number(a.twice); a.inc(5); number(a.use()); final b = B(); number(b.both()); b.x = 7; b.y = 20; number(b.both()); number(b.use()); final c = C(); c.inc(2); number(c.use()); number(c.both()); I d = D(); number(d.both()); truth(a is M); truth(b is N); truth(c is M); truth(d is A); truth(d is N); Object o = a; truth(o is N); M m = c; number(m.use()); M.st(); number(M.s); }
  ''');
  shows('call super, in order', '''
    class S { int f(int n) { print('S'); return n; } int get g => 1; set g(int v) { print('set'); number(v); } int operator +(int o) => o; int h = 4; }
    mixin A on S { @override int f(int n, [int z = 0]) { print('A'); return super.f(n + 1) * 10; } @override int get g => super.g + 10; @override set g(int v) { super.g = v + 1; } @override int operator +(int o) => super + (o + 5); @override int get h => super.h * 2; @override set h(int v) { super.h = v + 1; } }
    mixin B on S { @override int f(int n, [int k = 7]) { print('B'); return super.f(n + k) + 1; } @override int get g => super.g + 100; }
    class X extends S with A, B {} class Y extends S with B, A {} class Z extends X with A { @override int f(int n, [int k = 1]) { print('Z'); return super.f(n, k); } } class W = S with A;
    void t(S s) { number(s.f(1)); number(s.g); s.g = 5; number(s + 2); number(s.h); s.h = 20; number(s.h); }
    void main() { t(S()); t(X()); t(Y()); t(Z()); t(W()); number(X().f(1, 2)); int Function(int) q = Y().f; number(q(3)); truth(X().f == X().f); final x = X(); truth(x.f == x.f); }
  ''');
  shows('are generic', '''
    class Base<T> { T? t; T? get() => t; } mixin Store<T> on Base<T> { T? old; void put(T v) { old = t; t = v; } bool has(Object? o) => o is T; @override T? get() => super.get() ?? old; } mixin Pairs<X, Y> { X? a; Y? b; bool ok(Object? o) => o is X && o is! Y; List1<X> make() => List1<X>(); Y second(Y y) => b = y; }
    class List1<E> { bool holds(Object? o) => o is E; } class I extends Base<int> with Store<int> {} class G<T> extends Base<T> with Store<T>, Pairs<T, bool> {} class P with Pairs<int, double> {} class Q = G<num> with Pairs<num, bool>;
    void go(void Function() f) { try { f(); print('ok'); } on TypeError { print('T'); } }
    void main() { final i = I(); i.put(3); i.put(4); show(i.old); show(i.get()); truth(i.has(1)); truth(i.has(1.5)); final g = G<num>(); g.put(1.5); show(g.get()); truth(g.has(2)); truth(g.ok(2)); truth(g.make().holds(1.5)); final p = P(); truth(p.ok(1)); truth(p.ok(1.5)); p.a = 5; show(p.a); show(p.second(2)); Store<num> s = i; go(() => s.put(1.5)); go(() => s.put(8)); Object o = g; truth(o is Pairs<num, bool>); truth(o is Pairs<int, bool>); truth(o is Pairs<Object, Object>); truth(o is Store<int>); Pairs<Object, Object> w = p; go(() => w.second(1)); go(() => w.a = true); dynamic d = g; go(() => d.put(true)); go(() => d.put(2)); go(() => show(d.old)); final f = g.second; go(() => show(f(true))); }
  ''');
  shows(
    'initialize their fields in order',
    '''
    int n(int k) { number(k); return k; } class S { int a = n(1); S(int k) { number(k * 100); } S.named() : a = n(9); } mixin M { int b = n(2); late2() {} int bb = n(3); } mixin N { int c = n(4); Object? d; }
    class X extends S with M, N { int e = n(5); X() : super(n(6)) { number(a + b + bb + c + e); } X.two(super.k); X.three() : super.named(); } class Y = S with N, M; class Z extends Y { Z(super.k) { show(d); } Z.n() : super.named(); }
    void main() { X(); X.two(7); X.three(); Y(8); Y.named(); Z(9); Z.n(); final y = Y(1); y.d = 4; show(y.d); number(y.b); }
  '''
        .replaceAll('late2() {}', ''),
  );
  shows('have closures and constants', '''
    mixin M { int x = 1; int Function() f() => () => x++; int Function() get t => g; int g() => x * 10; } class A with M {} class B with M { B() { x = 5; } @override int g() => super.g() + 1; int Function() sup() => super.g; } mixin K { int get k => 7; } class C with K { final int n; const C(this.n); } class CC extends C { const CC() : super(4); @override int get k => super.k * n; }
    void main() { final a = A(), b = B(); final f = a.f(); number(f()); number(f()); number(a.x); number(b.t()); number(b.sup()()); number(b.f()()); number(const C(3).k); number(const CC().k); truth(identical(const CC(), const CC())); truth(const C(1) is K); }
  ''');
  shows('can be classes', '''
    mixin class M { int x = 2; int f() => x; } class A extends M { @override int f() => super.f() + 1; } class B with M { @override int f() => super.f() + 10; } abstract class J { int j(); } mixin H on J { int hh() => j() * 2; } class L implements J { @override int j() => 6; } class R extends L with H {}
    void main() { number(M().f()); number(A().f()); number(B().f()); number(R().hh()); H h = R(); number(h.hh()); number(h.j()); try { throw B(); } on M catch (m) { number(m.f()); } }
  ''');

  shows('late fields and local functions of mixins', '''
    class Z { int get k => 1; } mixin M on Z { late int a; late final b = k * 10; int c() { int f(int n) => n < 1 ? super.k : f(n - 1) + k; int g() { int h() => f(3) + b; return h(); } return g(); } int d() { late int x = super.k + k; void up() { x += 1; } up(); return x; } T e<T>(T t) { T id(T u) => u; return id(t); } }
    mixin N on Z { @override int get k => super.k + 5; } class A extends Z with M {} class B extends Z with N, M { @override int get k => 100; } class C = Z with N, M; class D extends A with M {}
    void main() { void use(M o) { number(o.b); number(o.c()); number(o.d()); number(o.e(o.b)); o.a = 4; number(o.a); } use(A()); use(B()); use(C()); use(D()); }
    ''');
  shows('super skips what takes more', '''
    class A { int f(int a) => a; int g({int x = 1}) => x; } mixin M on A { @override int f(int a, [int b = 2]) => super.f(a) + b; @override int g({int x = 2, int y = 3}) => super.g(x: x) * y; } mixin N on A { @override int f(int a, [int b = 5, int c = 7]) => super.f(a) + b * c; } class B extends A with M, N {}
    void main() { number(B().f(1)); number(B().f(1, 2, 3)); number(B().g()); number(B().g(y: 5)); A a = B(); number(a.f(4)); number(a.g(x: 9)); }
  ''');

  group('members of other classes', () {
    agrees('come from named mixins and noSuchMethod', r'''
      mixin Box<T> { late T item; Type get kind => T; T echo(T x) => item = x; }
      mixin class Nested<T> = Object with Box<T>;
      mixin class Twice<T> = Object with Nested<List<T>>;
      class Application<T>() with Twice<T>;
      class Plain extends Nested<int> {}
      abstract class Contract<T> { T value(T x, {int k = 3}); R generic<R extends T>(R x); Future<R> later<R>(FutureOr<R> f(T x)); set w(T x); T operator [](int i); }
      class Missing implements Contract<int> { dynamic noSuchMethod(Invocation i) { print((i.memberName == #later, i.positionalArguments.length, i.namedArguments.length, i.typeArguments)); return i.isSetter ? null : i.memberName == #later ? Future<String>.value('x') : 5; } }
      class Child extends Missing { int a() => super.value(1); int b() { final f = super.value; return f(2, k: 9); } int c() => super.generic<int>(7); int d() => super[3]; void e() { super.w = 8; } }
      class Wide implements Map<int, int> { dynamic noSuchMethod(i) => 0; int get length => 1; }
      class Other implements List<int> { dynamic noSuchMethod(i) => null; int get length => 2; }
      Stream<int> events(int count) async* {
        print('start');
        try { for (var i = 0; i < count; i++) { try { yield i; } finally { print('inner $i'); } } } finally { print('outer'); }
      }
      FutureOr<Iterable<int>> union() sync* { yield 1; }
      void main() async {
        final a = Application<String>(); a.item = ['a']; print((a.item, a.kind, a.echo(['b']), a is Nested<List<String>>, a is Box<List<String>>, a is Twice<String>));
        final p = Plain()..item = 4; print((p.item, p.kind));
        final c = Child(); print((c.a(), c.b(), c.c(), c.d())); c.e();
        Contract<num> n = Missing(); print(n.value(3)); try { n.value(1.5); } catch (e) { print(e); } try { n.w = 1.5; } catch (e) { print(e); }
        print(await n.later<String>((x) => 'y')); dynamic d = n; print(await d.later<String>((int x) => 'y')); try { d.value('x'); } catch (e) { print(e); }
        final t = n.value; print(t(4)); print(t is int Function(int)); try { (t as dynamic)('a'); } catch (e) { print(e); }
        dynamic w = Wide(); try { w.addAll({1: 2}); w.addAll([1]); } catch (e) { print(e.runtimeType); } print((w as Wide).length); Other()..addAll([1])..add(2);
        final s = events(2).listen((v) => print('v $v')); await s.cancel(); print('end');
        print((union() as Iterable<int>).toList());
      }
    ''', imports: "import 'dart:async';");
  });
}
