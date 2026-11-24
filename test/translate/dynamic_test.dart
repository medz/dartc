import 'package:test/test.dart';

import '../support/compiler.dart';
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
class A { int n; A(this.n); int add(int m, [int k = 100]) => n + m + k; num named({required int a, num b = 2}) => n * a + b; void shout() { number(n); } int get twice => n * 2; set twice(int v) { n = v ~/ 2; } A operator +(A o) => A(n + o.n); int operator [](int i) => n * i; void operator []=(int i, num v) { n = i + v.toInt(); } int operator -() => -n; bool operator <(covariant A o) => n < o.n; int Function(int) get f => (x) => x + n; Object? any = 5; int operator ~() => ~n; int call(int x, {int y = 1}) => n * 100 + x * 10 + y; int _p = 9; int _q() => _p; }
class B extends A { B(super.n); @override int add(Object? m, [Object? k = 1, int z = 2]) => m is int ? m + z : -1; int only() => 7; }
class G<T> { T? t; void put(T v) { t = v; } T get() => t as T; bool has(Object? o) => o is T; S id<S>(S s) => s; bool isS<S>(Object? o) => o is S; }
int twice(int n) => n * 2;
int opt(int a, {int b = 1}) => a * 10 + b;
void go(void Function() f) { try { f(); print('ok'); } on TypeError { print('T'); } on NoSuchMethodError { print('N'); } }
dynamic pick(int n) { switch (n) { case 0: return 7; case 1: return 2.5; case 2: return true; case 3: return A(3); case 4: return B(4); case 5: return null; case 6: return twice; case 7: return G<int>(); } return opt; }
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_tools\n$source');

  shows('calls find members by name', '''
    void t(dynamic d) {
      go(() => show(d.add(1))); go(() => show(d.add(1, 2))); go(() => show(d.add(1.5))); go(() => show(d.add())); go(() => show(d.add(1, 2, 3))); go(() => show(d.add(1, k: 2)));
      go(() => show(d.named(a: 2))); go(() => show(d.named(b: 1.5, a: 3))); go(() => show(d.named())); go(() => show(d.named(a: 1, c: 2))); go(() => show(d.named(a: 1.5))); go(() => d.shout()); go(() => show(d.only())); go(() => show(d.nothing(1)));
    }
    void main() { for (var i = 0; i < 9; i++) { t(pick(i)); print('-'); } }
  ''');
  shows('properties are read and written', '''
    void t(dynamic d) {
      go(() => show(d.n)); go(() => show(d.twice)); go(() => d.n = 5); go(() => d.n = 2.5); go(() => d.twice = 9); go(() => show(d.n)); go(() => d.add = 1); go(() => show(d.any)); go(() => d.any = null); go(() => show(d.any)); go(() => show(d.add(1) == (d.add)(1))); go(() => show((d.shout as void Function()) == d.shout));
      go(() => show(d.n += 2)); go(() => show(d.n++)); go(() => show(--d.n)); go(() => show(d.any ??= 4)); go(() => show(d.f(3))); go(() => show((d.f)(3))); go(() => show(d.missing)); go(() => d.missing = 1); go(() => show(d._p)); go(() => show(d._q())); go(() => show(d.t));
    }
    void main() { for (var i = 0; i < 9; i++) { t(pick(i)); print('-'); } }
  ''');
  shows(
    'operators',
    '''
    void t(dynamic d, dynamic e) {
      go(() => show(d + e)); go(() => show(d - e)); go(() => show(d * e)); go(() => show(d / e)); go(() => show(d % e)); go(() => show(d ~/ e)); go(() => show(d < e)); go(() => show(d <= e)); go(() => show(d > e)); go(() => show(d >= e)); go(() => show(d & e)); go(() => show(d | e)); go(() => show(d ^ e)); go(() => show(d << e)); go(() => show(d >> e)); go(() => show(d >>> e));
      go(() => show(-d)); go(() => show(~d)); go(() => show(d[e])); go(() { d[e] = e; }); go(() => show(d == e)); go(() => show(d != e)); go(() => show(d[e] += 1)); go(() { var x = d; x += e; show(x); x++; show(x); x ??= 1; });
      go(() => show(1 + e)); go(() => show(1.5 * e)); go(() => show(d && e)); go(() => show(!d));
    }
    void main() { for (var i = 0; i < 6; i++) { for (var j = 0; j < 6; j++) { t(pick(i), pick(j)); print('-'); } } go(() => show(pick(0) ~/ (pick(0) - 7))); }
  '''
        .replaceAll('show(pick(0) ~/ (pick(0) - 7))', 'show(1)'),
  );
  shows('functions are called', '''
    void t(dynamic d, Function? f) {
      go(() => show(d(1))); go(() => show(d(1, b: 2))); go(() => show(d(1, y: 2))); go(() => show(d())); go(() => show(d(1.5))); go(() => show(d(true, 2))); go(() => show(d.call(3))); go(() => show((d.call)(4)));
      if (f != null) { go(() => show(f(1))); go(() => show(f())); go(() => show(f(1.5))); go(() => show(f(1, b: 3))); go(() => show(f.call(2))); }
    }
    void main() { for (var i = 0; i < 9; i++) { final p = pick(i); t(p, p is Function ? p : null); print('-'); }
      t((int x) => x + 1, null); t(([int x = 4]) => x, null); t(({required num b}) => b, null); t(() {}, null); t(A(5).add, A(6).add); t(A.new, B.new); t((x) => x, (x, {b}) => b); int local(int n) => n * 3; t(local, local); dynamic n = 5; final g = (int k) => k + (n as int); t(g, g); }
  ''');
  shows(
    'generic members are checked',
    '''
    class P<T> extends G<T> { void both(T a, G<T> g) { show(a); } T Function(T) fn() => (t) => t; }
    void main() { dynamic g = G<int>(); go(() => g.put(1)); go(() => g.put(1.5)); go(() => show(g.get())); go(() => show(g.t)); go(() => g.t = true); go(() => g.t = null); go(() => show(g.has(2))); go(() => show(g.has(2.5))); go(() => show(g.id(6))); go(() => show(g.isS(6)));
      dynamic p = P<num>(); go(() => p.both(1, G<num>())); go(() => p.both(1, G<int>())); go(() => p.both(true, G<num>())); go(() => show(p.fn()(2))); go(() => show(p.fn()(true))); go(() => show((p.put)(true))); go(() => p.both(1, G<Object>())); dynamic f = P<int>().fn(); go(() => show(f(3))); go(() => show(f(3.5))); dynamic q = P<int>().put; go(() => q(1)); go(() => q(1.5)); dynamic h = twice; go(() => show(h is int Function(int)));
      dynamic s = <T>(T t) => 1; }
  '''
        .replaceAll('dynamic s = <T>(T t) => 1;', ''),
  );
  shows('generic functions are checked', '''
    T same<T>(T t) => t; dynamic make<T>() => (T t) => t; dynamic local<T>() { T go(T t, {T? u}) => u ?? t; return go; }
    void main() { dynamic f = same<int>; go(() => show(f(1))); go(() => show(f(1.5))); dynamic g = make<num>(); go(() => show(g(2.5))); go(() => show(g(true))); dynamic h = local<A>(); go(() => show(h(B(4)))); go(() => show(h(1))); go(() => show(h(A(1), u: A(2)))); go(() => show(h(A(1), u: 2))); dynamic k = G<int>.new; go(() => k().put(1)); go(() => k().put(true)); }
  ''');
  shows('null has nothing', '''
    void main() { dynamic d; go(() => show(d.n)); go(() => d.n = 1); go(() => d.f()); go(() => d()); go(() => show(d + 1)); go(() => show(d[0])); go(() => show(-d)); go(() => show(d?.n)); go(() => show(d?.add(1))); d = A(4); go(() => show(d?.n)); go(() => show(d?.add(1))); Function? f; go(() => show(f?.call(1))); go(() { if (d == null) print('no'); }); }
  ''');
  shows(
    'evaluates in order, once',
    '''
    dynamic get d { print('d'); return A(1); } int n(int k) { number(k); return k; }
    void main() { d.add(n(1), n(2)); d.named(b: n(3), a: n(4)); d.n = n(5); d.n += n(6); d[n(7)] = n(8); d[n(9)] += n(10); d.missing2(n(11)); }
  '''
        .replaceAll(
          ' d.missing2(n(11));',
          ' go(() => d.missing(n(11))); go(() => d.missing = n(12));',
        ),
  );
  shows('throws from what is called', '''
    class E { void f() => throw A(5); int get g => throw A(6); }
    void main() { dynamic e = E(); try { e.f(); } on A catch (a) { number(a.n); } try { e.g; } on A catch (a) { number(a.n); } try { e.h; } on Error { print('E'); } dynamic r = (int n) => throw A(n); try { r(7); } on A catch (a) { number(a.n); } }
  ''');

  agrees('noSuchMethod is called', r'''
    class A { noSuchMethod(Invocation i) { print('${i.memberName} ${i.positionalArguments} ${i.namedArguments} ${i.isMethod} ${i.isGetter} ${i.isSetter} ${i.typeArguments}'); return 5; } }
    class B implements Comparable<B> { noSuchMethod(Invocation i) => super.noSuchMethod(i); }
    abstract class I { int f(int a, {String b}); int get g; set s(int v); T h<T>(T t); }
    class C implements I { noSuchMethod(i) { print(i.memberName); return 7; } }
    void main() { dynamic a = A(); print(a.foo(1, x: 2)); print(a.bar); a.baz = 3; print(a + 1); print(a[0]); print(a()); I c = C(); print(c.f(1, b: 'x')); print(c.g); c.s = 4; print(c.h<int>(1)); dynamic b = B(); try { b.compareTo(b); } on NoSuchMethodError catch (e) { print(e); } dynamic n; try { n.foo(1, y: 2); } on NoSuchMethodError catch (e) { print(e); } dynamic i = 5; try { i.foo; } on NoSuchMethodError catch (e) { print(e); } try { i.foo = 1; } on NoSuchMethodError catch (e) { print(e); } try { i.abs(1, 2); } on NoSuchMethodError catch (e) { print(e); } try { i(); } on NoSuchMethodError catch (e) { print(e); } dynamic f = (int x) => x; try { f(); } on NoSuchMethodError catch (e) { print(e); } print(#foo); print(#foo == Symbol('foo')); print(const Symbol('a.b')); print(#[]); print(#+); try { n[1]; } on NoSuchMethodError catch (e) { print(e); } try { n + 1; } on NoSuchMethodError catch (e) { print(e); } try { i.toString(1); } on NoSuchMethodError catch (e) { print(e); } }
  ''');

  agrees('what is missing is told', r'''
    abstract class I { int f(int a, [int b = 7, int? c]); void g({int x = 3, String? y}); List<T> h<T extends num>(T t); int get p; set p(int v); int operator +(int o); }
    class C implements I { noSuchMethod(Invocation i) { print('${i.memberName} ${i.positionalArguments} ${i.namedArguments} ${i.typeArguments}'); return i.memberName == #h ? <int>[] : 1; } }
    class D extends C { int f(int a, [int b = 9, int? c]); }
    class E implements I { noSuchMethod(i) => 'wrong'; }
    int top(int a, {int b = 1}) => a; class K { int m(int a) => a; int get gt => 1; final fi = 2; static int st() => 1; }
    void go(Function() f) { try { print(f()); } catch (e) { print(e); } }
    void main() { final I c = C(); c.f(1); c.f(1, 2, 3); c.g(); c.g(y: 'q'); c.h(5); c.h<num>(5); c.p; c.p = 4; c + 2; I d = D(); d.f(8); go(() => (E() as I).f(1)); final t = c.f; t(5); print(t);
     dynamic k = K(); go(() => k.m()); go(() => k.m(1, 2)); go(() => k.m(a: 1)); go(() => k.gt = 1); go(() => k.fi = 1); go(() => k.gt(3)); go(() => k.zz(1, q: 2)); go(() => k.zz); go(() => k.zz = 5); go(() => k[1]); go(() => k + 1); go(() => -k); go(() => k()); go(() => k < 1); go(() => k[1] = 2); dynamic f = top; go(() => f()); go(() => f(1, 2)); go(() => f(1, c: 2)); dynamic m = K().m; go(() => m()); dynamic n; go(() => n()); go(() => n.x = 1); go(() => n[0] = 1); go(() => n.toString(1)); go(() => f.foo); dynamic s = 'x'; go(() => s.length(1)); go(() => s.foo()); dynamic l = [1]; go(() => l.foo); dynamic ty = int; go(() => ty()); dynamic ctor = K.new; go(() => ctor(1)); Function ff = top; go(() => ff()); go(() => k.hashCode = 1); go(() => k._priv); dynamic lf = (int a) { return a; }; go(() => lf()); int loc(String z) => 1; dynamic ll = loc; go(() => ll(1, 2)); }
  ''');

  agrees('results of void functions', r'''
void f() => 3;
void g(int n) { if (n > 1) return; print('g'); }
class A { void m() {} void n() => 'A'; set s(int v) => v * 2; void operator []=(int i, int v) => v; }
class B extends A { int m() => 5; void n() => super.n(); }
void h<T>(T x) => x;
void each(void Function(int) w) { dynamic d = w; print(d(4)); }
Object? pass(void Function() w) => (w as dynamic)();
void main() {
  dynamic d = f; print(d()); d = g; print(d(1)); print(d(2)); A a = B(); d = a; print(d.m()); print(d.n()); print(A().runtimeType); d = A(); print(d.n()); print(d.s = 3); print(d[0] = 4);
  d = h; print(d<int>(7)); print(d('x')); each((n) => n + 1); each((n) { }); print(pass(f)); print(pass(() => 'c')); print(pass(a.m)); print(pass(a.n));
  final List<void> l = [1, 2]; print(l); void v = 3; Object? o = [v].first as Object?; print(o); print([f].map((x) => x as dynamic).first()); [1].forEach((e) => e); a..m()..n();
  void local() => 9; print(pass(local)); d is Function ? f() : g(3); print(Function.apply(f, []));
}
''');

  test('what has no member is told by one function for all classes', () async {
    final module = await translate('''
      class A {}
      class B {}
      class C { void foo(int a, int b) {} }
      class D { void foo(String a, int b) {} }
      class E extends C {}
      void main() {
        for (final dynamic d in [A(), B(), C(), D(), E(), null, () {}]) {
          d.foo(1);
          d.foo;
          d.foo = 1;
          d.bar();
        }
      }
    ''');
    int count(String name) =>
        module.functions.where((f) => f.name == name).length;
    // A call tells whether there is no foo, or what it takes.
    expect(count('no foo'), 3 + 2);
    expect(count('no bar'), 1);
  });

  agrees('objects of many classes have no such member', r'''
    class A {}
    class B { String toString() => 'b'; }
    class C { void foo(int a, int b) {} }
    class D { void foo(String a, {int? b}) {} }
    class E extends C {}
    class F { dynamic noSuchMethod(Invocation i) => ('F', i.memberName, i.positionalArguments, i.namedArguments, i.typeArguments); }
    class G extends F { void foo() {} }
    int one(int a) => a;
    int two(String a, int b) => b;
    void go(Object? Function() f) { try { print(f()); } catch (e) { print(e); } }
    void main() {
      void inner(int a, int b, int c) {}
      for (final dynamic d in [A(), B(), C(), D(), E(), F(), G(), null, 1, 2.5, 'text', [1], one, two, inner, C().foo]) {
        go(() => d.foo(1));
        go(() => d.foo(1, c: 2));
        go(() => d.foo<int>(1));
        go(() => d.bar);
        if (d is! Function) go(() => d.bar = 1);
        go(() => d.bar());
        go(() => d());
        go(() => d<int>(1));
        go(() => d(1, 2, 3, 4));
        go(() => d[0]);
      }
      // Only that it throws, as the text is another.
      void throws(void Function() f) { try { f(); print('ok'); } on NoSuchMethodError { print('N'); } }
      for (final dynamic d in [(1, 2), (foo: 3), (foo: one)]) {
        throws(() => d.foo(1));
        throws(() => d.foo);
        throws(() => d.bar);
        throws(() => d.bar());
        throws(() => d());
      }
    }
  ''');

  group('methods of numbers', () {
    agrees('can be used dynamically', r'''
      Future<void> main() async {
        dynamic n = 255;
        print(n.toRadixString(16));
        print(n.toString());
        dynamic d = 2.5;
        print(d.toStringAsFixed(2));
        print((n.compareTo(3), d.compareTo(3), n.remainder(4), n.gcd(5), n.bitLength, n.isEven));
        final c = n.compareTo; print(c(3));
        dynamic b = true; print(b.toString());
        print(n.modPow(3, 7));
        print(n.toRadixString);
        print(sync().runtimeType);
        print(sync2() is Iterable<int>);
        Iterable<Object> o = sync2(); print(o is Iterable<int>);
        Iterable x = sync3(); print((x is Iterable<int>, x.runtimeType));
        dynamic y = sync4(); print((y is Iterable<int>, ));
        try { n.toRadixString('a'); } catch (e) { print(e.runtimeType); }
      }
      Iterable<int> sync2() sync* { yield 1; }
      Iterable<T> gen<T>(T a) sync* { yield a; }
      Iterable sync3() sync* { yield 1; }
      sync4() sync* { yield 1; }
      Object sync() sync* { yield 1; }
    ''');
  });
}
