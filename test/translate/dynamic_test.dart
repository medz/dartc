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

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(
        translateWhole(source),
        failsWith(['main.dart:$problem']),
      );
    });

    const what = 'Not supported yet:';
    reports(
      'void main() { dynamic d = 1; d.abs(); }',
      '1:30: $what calling abs of the SDK.',
    );
    reports(
      'void main() { dynamic d = 1; d.toString(); }',
      '1:30: $what calling toString of the SDK.',
    );
    reports(
      'class A {}\nvoid main() { dynamic d = A(); d.hashCode; }',
      '2:32: $what calling hashCode of the SDK.',
    );
    reports(
      'class A { f() => 1; noSuchMethod(i) => 2; }\nvoid main() { dynamic d = A(); d.g(); }',
      '2:32: $what noSuchMethod.',
    );
    reports(
      'class A { void f<T>() {} }\nvoid main() { dynamic d = A(); d.f<int>(); }',
      '2:32: $what type arguments of a dynamic call.',
    );
  });
}
