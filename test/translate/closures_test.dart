import 'package:test/test.dart';

import '../support/new_compiler.dart';
import 'support.dart';

const _tools = r'''
void show(Object? o) {
  if (o == null) { print('null'); }
  else if (o is int) { number(o); }
  else if (o is bool) { truth(o); }
  else if (o is double) { print('double'); number((o * 2).toInt()); }
  else { print('other'); }
}
int twice(int n) => n * 2;
int apply(int Function(int) f, int n) => f(n);
void run(void Function() f) => f();
class A { final int n; const A(this.n); int add(int m) => n + m; void shout() => number(n); int get g => n; }
class B extends A { const B(super.n); @override int add(int m, [int k = 100]) => n + m + k; }
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_tools\n$source');

  group('functions are values', () {
    shows('of libraries and classes', '''
      class S { static int half(int n) => n ~/ 2; static int Function(int) f = twice; int Function(int) g = half; }
      int Function(int) pick(bool b) => b ? twice : S.half;
      void main() {
        number(apply(twice, 4)); number(apply(S.half, 9)); number(pick(true)(5)); number(pick(false)(8));
        var f = twice; number(f(3)); f = S.half; number(f(3)); number(f.call(7)); final g = f.call; number(g(20));
        number(S.f(6)); S.f = S.half; number(S.f(6)); number(S().g(10)); final s = S(); s.g = twice; number(s.g(10)); number((s.g)(11));
        truth(twice == twice); truth(identical(twice, twice)); truth(twice == S.half); Object o = twice; truth(o == twice); truth(o == f);
        int Function(int)? n; truth(n == null); n = twice; number(n(1)); n = null; show(n?.call(3)); show((n ?? S.half)(100));
      }
    ''');
    shows('with every kind of parameter', '''
      int opt(int a, [int b = 10, int c = 100]) => a + b + c;
      int named(int a, {int b = 10, required int c}) => a * 1000 + b * 100 + c;
      double mix(double d, bool b, Object? o, num n, int? i) { show(o); show(n); show(i); return b ? d : -d; }
      void nothing() { print('nothing'); }
      dynamic any() => 5; A make(A a) => a; Never fail(int n) => throw A(n);
      void main() {
        int Function(int) f = opt; number(f(1)); int Function(int, int) g = opt; number(g(1, 2)); var h = opt; number(h(1)); number(h(1, 2)); number(h(1, 2, 3));
        int Function(int, {required int c}) k = named; number(k(1, c: 5)); var m = named; number(m(1, c: 5)); number(m(1, c: 5, b: 6)); number(m(c: trace(7), b: trace(8), trace(9)));
        final x = mix; truth(x(1.5, false, 3, 4, null) < 0); truth(x(2, true, null, 1.5, 7) == 2);
        run(nothing); var v = nothing; v(); var d = any; show(d()); Object? Function() e = any; show(e()); void Function() w = any; w();
        A Function(B) c = make; number(c(B(4)).n); num Function(int) z = twice; show(z(8)); Object Function(int) y = twice; show(y(9));
        int Function(int) q = fail; try { q(3); } on A catch (e) { number(e.n); }
      }
    ''');
    shows('of objects', '''
      class C { int n = 1; int inc() => ++n; void set(int v) { n = v; } C self() => this; int Function() both() { return inc; } int call(int a, [int b = 5]) => n * 100 + a * 10 + b; }
      class D extends C { @override int inc() => n += 10; int Function() sup() => super.inc; int Function() own() => inc; int Function() mine() => this.inc; }
      void main() {
        final c = C(); final f = c.inc; number(f()); number(f()); number(c.n); c.set(50); number(f()); final s = c.set; s(7); number(c.n);
        C d = D(); number(d.inc()); number(d.both()()); number(D().sup()()); number(D().own()()); number((d as D).mine()());
        truth(c.inc == c.inc); truth(c.inc == f); truth(c.inc == C().inc); truth(identical(c.inc, c.inc)); truth(c.inc == c.self().inc); truth(d.inc == c.inc); Object o = c.inc; truth(o == f); truth(f == c.set);
        number(c(2)); number(c(2, 3)); number(c.call(4)); int Function(int) g = c; number(g(6)); number(apply(c, 1)); final h = c.call; number(h(1, 1));
        final A a = B(3); number(a.add(1)); final add = a.add; number(add(1)); number(apply(a.add, 2)); final b = B(4); number(b.add(1, 2)); int Function(int, int) two = b.add; number(two(3, 4));
        run(a.shout); C? n; show(n?.inc); n = c; number(n.inc()); final Function x = c.inc; truth(x == c.inc);
      }
    ''');
    shows('of constructors', '''
      class P { final int n; P(this.n, [int k = 1]) { number(n + k); } P.twice(int n) : this(n * 2); factory P.made(int n) => P(n + 1000); P.none() : n = 0; }
      P build(P Function(int) f, int n) => f(n);
      void main() {
        number(build(P.new, 3).n); number(build(P.twice, 4).n); number(build(P.made, 5).n); final f = P.none; number(f().n); final g = P.new; number(g(6, 7).n);
        truth(P.new == P.new); truth(P.twice == P.new); A Function(int) a = B.new; number(a(9).add(1));
      }
    ''');
    shows('that are constant', '''
      class K { final int Function(int) f; final Object o; const K(this.f, [this.o = twice]); }
      const int Function(int) c = twice; const k = K(twice); int def(int n, [int Function(int) f = twice]) => f(n); int Function(int) g = c;
      class S { static int t(int n) => n * 3; static const K s = K(t, S.t); }
      void main() {
        number(c(4)); number(k.f(5)); truth(identical(k, const K(twice))); number(def(6)); number(def(6, S.t)); number(g(7)); number(S.s.f(8)); truth(k.o == twice); truth(S.s.o == S.t); truth(identical(c, twice));
      }
    ''');
  });

  group('closures', () {
    shows('take arguments and give results', '''
      void main() {
        number(apply((n) => n + 1, 4)); number(apply((int n) { return n * n; }, 5)); run(() => print('run')); run(() { print('block'); });
        final f = (int a, [int b = 2, int? c]) => a * 100 + b * 10 + (c ?? 0); number(f(1)); number(f(1, 5)); number(f(1, 5, 7));
        final g = ({int a = 1, required int b}) => a - b; number(g(b: 4)); number(g(b: 4, a: 9)); final h = (double d, bool b) => b ? d : -d; truth(h(1.5, false) == -1.5);
        number((() => 7)()); number(((int n) => n)(8)); Object? Function(Object?) k = (o) => o; show(k(3)); show(k(null)); show(k(true)); final w = () {}; w(); dynamic Function() z = () {}; show(z());
        int Function(int) Function(int) add = (a) => (b) => a + b; number(add(3)(4)); final A Function() m = () => A(6); number(m().n);
      }
    ''');
    shows('see the variables around them', '''
      int Function() counter(int from) { var n = from; return () => n++; }
      void main() {
        final a = 5; var b = 6; number((() => a + b)()); b = 7; number((() => a + b)());
        final c = counter(10), d = counter(20); number(c()); number(c()); number(d()); number(c());
        var sum = 0; void add(int n) { sum += n; } add(3); add(4); number(sum); final f = add; f(5); number(sum); run(() => sum = 100); number(sum);
        int x; x = 1; final g = () => x; x = 2; number(g()); double dd = 1.5; bool bb = true; A? aa; Object? oo = 4; final t = () { dd += 1; bb = !bb; aa = A(dd.toInt()); oo = null; }; t(); truth(dd == 2.5); truth(bb); number(aa?.n ?? -1); show(oo);
        num m = 1; run(() => m = 2.5); show(m); int? z; run(() { z = (z ?? 0) + 1; }); show(z);
      }
    ''');
    shows('see parameters, and nest', '''
      int Function(int) outer(int a, {int b = 2}) { a += 1; return (c) { b++; int inner(int d) { a += d; return a * 1000 + b * 100 + c * 10 + d; } return inner(c); }; }
      void deep(int n) { void go(int k) { if (k > 0) { final here = k; run(() => run(() => run(() { n += here; go(k - 1); }))); } } go(n); number(n); }
      void main() { final f = outer(3); number(f(4)); number(f(5)); number(outer(1, b: 7)(2)); deep(4); }
    ''');
    shows('have their own variables in every round', '''
      void main() {
        int Function()? a, b, c; for (var i = 0; i < 3; i++) { if (i == 0) a = () => i; if (i == 1) b = () => i; if (i == 2) c = () => i++; } show(a?.call()); show(b?.call()); show(c?.call()); show(c?.call());
        for (var i = 0, j = 10; i < j; i += 3) { final f = () { j--; i++; return i * 100 + j; }; number(f()); number(i); number(j); }
        int Function()? last; var n = 0; while (n < 3) { var k = n * 10; k++; final old = last; last = () => k++ + (old == null ? 0 : old()); n++; } show(last?.call()); show(last?.call());
        do { var q = n; run(() => q++); number(q); } while (--n > 0); for (var i = 0; i < 2; i++) { int? u; show(u); run(() => u = i); show(u); }
        for (var i = 0; i < 4; i++) { if (i == 1) continue; final f = () => i; if (i == 3) break; number(f()); }
      }
    ''');
    shows(
      'see this',
      '''
      class P { int n = 1; int Function() get get => () => n; void Function(int) set() => (v) { n = v; this.n += 1; }; late2() { return () => self().n; } P self() => this; int field = 3; final int Function(int) f = (x) => x + 1;
        int Function() twice() { return () { int go() => n * 2 + inc(); return go(); }; } int inc() => ++n; P Function() me() => () => this; }
      class Q extends P { @override int inc() => n += 100; int Function() sup() => () => super.inc(); int Function() s2() { return () { return super.n; }; } }
      void main() {
        final p = P(); final g = p.get, s = p.set(); number(g()); s(5); number(g()); number(p.twice()()); truth(p.me()() == p); number(p.f(6)); final q = Q(); number(q.twice()()); number(q.sup()()); number(q.s2()()); number(p.late2()());
      }
    '''
          .replaceAll('late2()', 'lateTwo()')
          .replaceAll('lateTwo() {', 'int Function() lateTwo() {'),
    );
    shows('are used in constructors and fields', '''
      class P { final int Function() a; int Function(int)? b; P(int n) : a = (() => n * 2) { var m = n; b = (k) => m += k; } P.init(int n, {int Function(int)? this.b}) : a = (() { n++; return n; }); }
      int Function() g = () { var n = 0; return () => ++n; }(); final k = (() => 5)(); class S { static int Function(int) s = (n) => n * k; }
      void main() { final p = P(4); number(p.a()); number(p.b!(3)); number(p.b!(3)); final q = P.init(6, b: (x) => -x); number(q.a()); number(q.a()); show(q.b?.call(9)); number(g()); number(g()); number(S.s(3)); }
    ''');
    shows('name themselves', '''
      void main() {
        int fact(int n) => n < 2 ? 1 : n * fact(n - 1); number(fact(5)); bool isEven(int n) { bool odd(int m) => m == 0 ? false : isEven(m - 1); return n == 0 ? true : odd(n - 1); } truth(isEven(10)); truth(isEven(7));
        int total = 0; void walk(int n) { if (n == 0) return; total += n; final next = walk; next(n - 1); } walk(4); number(total); truth(fact == fact); int f({int a = 1}) => a; number(f()); number(f(a: 3));
      }
    ''');
    shows('work with exceptions', '''
      void main() {
        var n = 0; final f = (int k) { try { n += k; if (k > 2) throw A(k); return n; } on A catch (e) { run(() => n += e.n * 10); rethrow; } finally { run(() => n++); } };
        number(f(1)); try { f(3); } on A catch (e) { run(() => number(e.n)); } number(n); try { run(() => throw B(5)); } on B catch (e) { number(e.n); }
        for (var i = 0; i < 3; i++) { try { run(() { if (i == 1) throw A(i); number(i); }); } catch (e) { print('caught'); continue; } finally { run(() => n += i); } } number(n);
        var x = 1; try { x = 2; run(() { x = 3; throw C(); }); } on C { number(x); }
      }
      class C implements Exception {}
    ''');
    shows(
      'survive collections',
      '''
      class L { L? next; int n = 0; } void main() { int Function()? f; for (var i = 0; i < 50; i++) { final l = L()..n = i; } }
    '''
          .replaceAll(
            'final l = L()..n = i;',
            'final l = L(); l.n = i; final old = f; var c = 0; f = () { c += l.n; return c + (old == null ? 0 : old()); };',
          )
          .replaceAll('} }\n', '} show(f?.call()); show(f?.call()); }\n'),
    );
  });

  group('function types', () {
    shows('are tested', '''
      int opt(int a, [int b = 1]) => a; void named({int x = 1}) {} A back(Object o) => A(1); Object? pick(int n) { switch (n) { case 0: return twice; case 1: return opt; case 2: return named; case 3: return back; case 4: return () => 1; case 5: return A(1).shout; case 6: return 5; case 7: return null; case 8: return B(2).add; case 9: return A.new; } return A(2).add; }
      void main() { for (var i = 0; i < 11; i++) { final o = pick(i); truth(o is Function); truth(o is int Function(int)); truth(o is void Function()); truth(o is num Function(int)); truth(o is A Function(A)); truth(o is void Function({int x})); truth(o is int Function(int, int)); truth(o is int Function(int)?); truth(o is Object); truth(o is A); truth(o is! Function); truth(o is dynamic Function(Never)); truth(o is Object? Function()); }
        Object o = twice; if (o is int Function(int)) number(o(4)); number((o as int Function(int))(5)); try { o as void Function(); } on TypeError { print('a'); } try { Object? n; n as Function; } on TypeError { print('b'); } Object f = () => 3; final g = f as Function; truth(g == f); }
    ''');
    for (final (name, body) in [
      ('static', 'o = twice; o as void Function();'),
      ('closure', 'o = (String2 a, {int? b}) => true; o as A;'),
      ('optional', 'o = ([int a = 1]) {}; o as int;'),
    ]) {
      shows(
        'name what is wrong: $name',
        "class String2 {} void main() { print('a'); Object o; $body }",
      );
    }
    shows('of overrides', '''
      class P { void f(int Function(B) g) => number(g(B(1))); num Function(int) h() => twice; A Function()? k; }
      class Q extends P { @override void f(Object? g) { print('Q'); } @override int Function(num) h() => (n) => n.toInt() + 1; @override covariant B Function()? k; }
      void use(P p) { p.f((b) => b.n); show(p.h()(4)); p.k = () => B(7); number(p.k!().n); try { p.k = () => A(8); number(p.k!().n); } on TypeError { print('T'); } }
      void main() { use(P()); use(Q()); }
    ''');
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(translate(source), failsWith(['main.dart:$problem']));
    });

    const what = 'Not supported yet:';
    reports(
      'void main() { final f = () async {}; f(); }',
      '1:28: $what async and generator functions.',
    );
  });

  agrees('generic functions are values', r'''
    T id<T>(T t) => t; class A { T m<T>(T t) => t; Type k<T>() => T; static S s<S>(S s) => s; } typedef F = T Function<T>(T);
    void main() { F f = id; print(f<int>(1)); print(f('x')); final g = A().m; print(g<int>(3)); int Function(int) h = A().m; print(h(4)); F k = A.s; print(k(2.5)); T local<T>(T t) => t; F l = local; print(l(true)); print(f is F); print(f.runtimeType); dynamic d = f; print(d<int>(1)); print(d(2)); var t = A().k; print(t<int>()); print([id][0]('z')); print(id == f); final e = <T>(T x) => [x]; print(e<num>(1)); print(e('a').runtimeType); print(f); }
  ''');

  agrees('loops give each round its own variables', r'''
    void main() { final fs = <int Function()>[]; for (final x in [1, 2, 3]) { fs.add(() => x); } for (var y in [4, 5]) { y++; fs.add(() => y++); } print(fs.map((f) => f()).toList()); print(fs.map((f) => f()).toList()); final l = [1, 2]; l[0] |= 6; l[1]++; l[0] <<= 2; print(l); final m = {'a': 1}; m['a'] = m['a']! + 1; m['b'] ??= 5; print(m); int z; for (z in l) { fs.add(() => z); } print(fs.last()); }
  ''');
}
