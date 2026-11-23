import 'package:test/test.dart';

import '../support/new_compiler.dart';
import 'support.dart';

/// Classes to throw, and ways to do so.
const _errors = r'''
class A { final int n; A(this.n); }
class B extends A { B(super.n); }
class C implements Exception { const C(); }
class D extends Error {}
abstract class I {}
class J extends A implements I { J(super.n); }
int raise(int n) { if (n > 0) throw A(n); return n; }
void any(int n) {
  switch (n) {
    case 1: throw A(1); case 2: throw B(2); case 3: throw C();
    case 4: throw D(); case 5: throw J(5); case 6: throw const C();
  }
}
int zero() => 0;
A? none() => null;
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_errors\n$source');

  group('throw', () {
    shows('leaves functions until it is caught', '''
      int f(int n) { number(n); final r = raise(n) + 1; number(r); return r; }
      int g(int n) { final r = f(n); print('g'); return r; }
      void main() {
        number(g(0));
        try { number(g(3)); print('no'); } catch (e) { print('caught'); }
        print('after');
      }
    ''');
    shows('is an expression', '''
      A pick(A? a) => a ?? (throw C());
      int choose(bool b) => b ? 1 : throw A(2);
      bool both(bool b) => b && (throw D());
      Never fail() => throw B(7);
      int add(int a, int b) => a + b;
      int arrow() => throw A(9);
      void main() {
        number(pick(A(4)).n); number(choose(true)); truth(both(false));
        try { pick(null); } on C { print('C'); }
        try { choose(false); } on A catch (e) { number(e.n); }
        try { both(true); } on D { print('D'); }
        try { fail(); } on B catch (e) { number(e.n); }
        try { number(arrow()); } on A catch (e) { number(e.n); }
        try { number(add(trace(1), throw A(trace(5)))); } on A catch (e) { number(e.n); }
      }
    ''');
    shows('ends the program where nothing catches it', '''
      void main() { print('a'); try { raise(3); } finally { print('f'); } }
    ''');
    shows('may happen in constructors, getters and operators', '''
      class P {
        int x; int y = raise(zero());
        P(this.x) { if (x > 2) throw A(x); }
        int get z => x > 1 ? throw A(10 + x) : x;
        set z(int v) { if (v > 1) throw A(20 + v); x = v; }
        P operator +(P o) => throw A(30 + o.x);
        bool operator ==(Object o) => throw A(40);
      }
      void t(int n) {
        try {
          final p = P(n);
          switch (n) {
            case 0: p.z = 1; number(p.z); p.z = 9;
            case 1: p + p;
            case 2: p.z;
          }
          number(p == p ? 1 : 0);
        } on A catch (e) { number(e.n); }
      }
      void main() { t(0); t(1); t(2); t(3); }
    ''');
  });

  group('catch', () {
    shows('chooses by class, in order', '''
      void t(int n) {
        try { any(n); print('none'); }
        on B catch (e) { print('B'); number(e.n); }
        on I { print('I'); }
        on A catch (e) { print('A'); number(e.n); }
        on Exception { print('Exception'); }
        on Error catch (e) { print('Error'); }
      }
      void main() { for (var i = 0; i < 7; i++) t(i); }
    ''');
    shows('passes on what it does not catch', '''
      void t(int n) {
        try { any(n); } on B { print('B'); } on Error { print('Error'); }
      }
      void main() {
        for (var i = 0; i < 7; i++) {
          try { t(i); print('none'); } on Exception { print('Exception'); }
          catch (e) { print('other'); }
        }
      }
    ''');
    shows('takes objects and traces', '''
      void main() {
        final a = A(3);
        try { throw a; } catch (e, s) {
          truth(identical(e, a)); truth(e == a); truth(s == s);
          final StackTrace t = s; truth(identical(s, t));
        }
        try { throw a; } on Object catch (e, _) { truth(e == a); }
        try { throw a; } on A catch (e) { number(e.n); A b = e; b = B(4); number(b.n); }
      }
    ''');
    shows('sees the variables as they were', '''
      void main() {
        var a = 1, b = 2.5; var c = true; A? d; int e;
        try {
          a = 2; raise(0); b = 3.5; d = A(a); a = raise(5); c = false;
        } on A catch (x) { number(a); truth(b == 3.5); truth(c); number(x.n); a += 10; }
        number(a); truth(d != null);
        for (var i = 0; i < 5; i++) {
          try { a = i; if (i == 3) raise(i); b = b + 1; } catch (_) { a = -a; }
          number(a);
        }
        truth(b == 7.5);
        e = 4; try { e = raise(1); } catch (_) {} number(e);
      }
    ''');
    shows('nests', '''
      void t(int n) {
        try {
          try { any(n); } on C { print('C'); any(1); } on D { print('D'); throw C(); }
          print('inner');
        } on A catch (e) {
          number(e.n);
          try { any(3); } on C { print('again'); any(n); }
        } on C { print('outer'); }
      }
      void main() {
        for (var i = 0; i < 7; i++) { try { t(i); } catch (e) { print('out'); } }
      }
    ''');
    shows('rethrows the same object', '''
      void t(A a) {
        try { throw a; } on A catch (e) {
          try { throw C(); } on C { print('C'); }
          rethrow;
        }
      }
      void main() {
        final a = A(6);
        try { t(a); } catch (e) { truth(e == a); }
      }
    ''');
    shows('works in loops, with break and continue', '''
      void main() {
        var n = 0;
        while (true) {
          try { n++; if (n == 2) continue; if (n == 7) break; raise(n); }
          on A catch (e) { if (e.n == 4) continue; number(e.n); if (n == 6) raise(0); }
        }
        number(n);
        outer: for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            try { raise(i * j); } catch (_) { if (j == 3) continue outer; if (i == 3) break outer; }
            number(i * 10 + j);
          }
        }
      }
    ''');
    shows('returns from functions', '''
      int f(int n) { try { return raise(n) + 100; } on A catch (e) { return e.n; } }
      int g(int n) { try { if (n > 2) return 1; any(n); } catch (e) { return 2; } return 3; }
      void main() { number(f(0)); number(f(6)); for (var i = 0; i < 5; i++) number(g(i)); }
    ''');
  });

  group('finally', () {
    shows('runs however its body ends', '''
      int f(int n) {
        try {
          if (n == 0) return 10;
          if (n == 1) return raise(1);
          number(n);
        } finally { print('f'); }
        return 20;
      }
      void main() {
        number(f(0)); number(f(2));
        try { number(f(1)); } on A catch (e) { number(e.n); }
      }
    ''');
    shows('runs after a catch, however that ends', '''
      int f(int n) {
        try { any(n); number(n); }
        on B { return 50; }
        on A catch (e) { number(e.n); }
        on C { throw D(); }
        finally { print('f'); }
        return 60;
      }
      void main() {
        for (var i = 0; i < 6; i++) {
          try { number(f(i)); } on D { print('D'); } catch (e) { print('other'); }
        }
      }
    ''');
    shows('may replace how its body ends', '''
      int f(int n) { try { any(n); return 1; } finally { if (n == 1) return 2; if (n == 2) throw D(); } }
      int g() { while (true) { try { return 1; } finally { break; } } return 2; }
      int h() { for (var i = 0; ; i++) { try { if (i > 2) return i; raise(1); } finally { if (i < 5) continue; } } }
      void main() {
        for (var i = 0; i < 4; i++) { try { number(f(i)); } on D { print('D'); } catch (e) { print('other'); } }
        number(g()); number(h());
      }
    ''');
    shows('nests, for every way out', '''
      int f(int n) {
        var r = 0;
        outer: for (var i = 0; i < 3; i++) {
          try {
            try {
              try {
                if (n == 1) return trace(i + 70);
                if (n == 2) break;
                if (n == 3) continue;
                if (n == 4) break outer;
                if (n == 5) raise(5);
                if (n == 6) any(3);
                r += 1;
              } finally { print('a'); r += 10; number(i); }
            } on A { print('A'); } finally { print('b'); }
          } finally { print('c'); if (n == 7) r *= 2; }
        }
        return r;
      }
      void main() {
        for (var i = 0; i < 8; i++) { try { number(f(i)); } on C { print('C'); } }
      }
    ''');
    shows('keeps the value returned before it', '''
      int x = 1;
      int f() { var r = 5; try { return r; } finally { r = 6; x = 2; } }
      double g() { try { return 2.5; } finally { x++; } }
      bool h() { try { return x > 2; } finally { x = 0; } }
      A k() { final a = A(x); try { return a; } finally { x = 9; } }
      void v() { try { return; } finally { print('v'); } }
      void main() { number(f()); truth(g() == 2.5); truth(h()); number(k().n); v(); number(x); }
    ''');
    shows('comes after variables that end with the body', '''
      void main() {
        try { int v; if (zero() == 0) { v = 1; } else { v = 2; } number(v); }
        finally { number(3); int w; w = 4; number(w); }
        for (var i = 0; i < 2; i++) {
          try { var v = i; v++; raise(i); number(v); }
          on A catch (e) { var v = 5; v += e.n; number(v); }
          finally { var v = 6; v--; number(v); }
        }
      }
    ''');
    shows('contains other tries', '''
      void f(int n) {
        try { raise(n); } finally {
          try { any(3); } on C { print('C'); } finally { print('in'); }
          for (var i = 0; i < 2; i++) { try { raise(i); } catch (_) { continue; } finally { number(i); } }
        }
        print('end');
      }
      void main() { f(0); try { f(1); } on A { print('A'); } }
    ''');
    shows('does not run when the program exits', '''
      void main() { print('a'); try { exit(4); } finally { print('f'); } }
    ''');
  });

  group('errors of operators', () {
    shows('division by zero', '''
      void main() {
        final z = zero(); var x = 7;
        try { x ~/ z; } on IntegerDivisionByZeroException { print('a'); }
        try { x % z; } on UnsupportedError { print('b'); }
        try { x ~/= z; } on Exception { print('c'); }
        try { x %= 0; } on Error { print('d'); }
        number(x); number(x ~/ (z + 2)); number(-7 % (z - 3)); number(7 % (z - 3));
        number(x ~/ (z - 1)); number(-9223372036854775808 % (z - 1));
        number(-9223372036854775808 ~/ (z - 1));
        number(-7 % (z - 9223372036854775807 - 1));
      }
    ''');
    shows('shifts', '''
      void main() {
        final z = zero();
        try { 1 << (z - 1); } on ArgumentError { print('a'); }
        try { 1 >> (z - 5); } on Error { print('b'); }
        try { 1 >>> -1; } on ArgumentError { print('c'); }
        number(1 << (z + 5)); number(1 << (z + 63)); number(1 << (z + 64));
        number(-9 >> (z + 2)); number(-9 >> (z + 63)); number(-9 >> (z + 64));
        number(-9 >> (z + 9223372036854775807)); number(9 >> (z + 100));
        number(-9 >>> (z + 60)); number(-9 >>> (z + 64)); number(9 >>> (z + 1));
        var x = 3; x <<= z + 2; x >>= z + 1; x >>>= z; number(x);
      }
    ''');
    shows('numbers without an int', '''
      double inf = 1 / 0, nan = 0 / 0;
      void t(double d) {
        try { number(d.toInt()); } on UnsupportedError { print('u'); }
        try { number(d ~/ 2); } on UnsupportedError { print('v'); }
        try { number(d ~/ zero()); } on UnsupportedError { print('w'); }
        try { number(5 ~/ d); } on Error { print('x'); }
      }
      void main() {
        t(0); t(-0.0); t(2.5); t(-7.9); t(1e300); t(-1e300); t(inf); t(-inf); t(nan);
        t(9223372036854774784.0); t(9223372036854775808.0); t(-9223372036854775808.0);
        number(7.toInt()); var i = 9; i ~/= 2.5; number(i); number((0.1 + 0.2).toInt());
      }
    ''');
    shows('null where an object is needed', '''
      A? some(bool b) => b ? A(8) : null;
      void main() {
        number(some(true)!.n);
        try { number(some(false)!.n); } on TypeError { print('a'); }
        final A a = some(true)!; number(a.n);
        number(zero()!); A? x = some(false);
        try { x!; } on Error catch (e) { print('b'); }
        x = A(3); number(x.n); number(zero()!);
        final B? b = null; try { print('c'); raise(b!.n); } on TypeError { print('d'); }
      }
    ''');
    for (final (name, body) in [
      ('division', '1 ~/ zero();'),
      ('modulo', '1 % zero();'),
      ('shift', '1 << (zero() - 12345);'),
      ('smallest shift', '1 >> (zero() - 9223372036854775807 - 1);'),
      ('toInt', '(1.5 / zero()).toInt();'),
      ('null', 'none()!;'),
      ('user class', 'raise(1);'),
      ('exception', 'throw C();'),
      ('error', 'throw D();'),
    ]) {
      shows('end the program: $name', "void main() { print('a'); $body }");
    }
    shows('end the program with the text of the object', r'''
      const name = 'my';
      class T implements Exception { String toString() => '$name error é'; }
      class U extends T {}
      class _V { @override String toString() { return 'V'; } }
      void main() {
        print('a');
        try { throw _V(); } on _V { print('V'); }
        throw U();
      }
    ''');
    shows('end the program: a private class', '''
      class _V {}
      void main() { print('a'); throw _V(); }
    ''');
    shows('end the program: a variable set while being set', '''
      int n = 0;
      int f() => ++n == 1 ? x + 1 : 5;
      final int x = f();
      class S { static final int y = g(); static int g() => ++n == 4 ? y + 1 : 5; }
      void main() {
        print('a');
        try { number(x); } on Error { print('E'); }
        number(x); number(n); n = 3; number(S.y);
      }
    ''');
    shows('leave variables unset', '''
      int tries = 0;
      int x = f();
      int f() { if (++tries < 3) throw A(tries); return 40 + tries; }
      void main() {
        for (var i = 0; i < 4; i++) { try { number(x); } on A catch (e) { number(-e.n); } }
        number(tries);
      }
    ''');
  });

  group('the stack', () {
    shows('overflows as an error', '''
      int f(int n) => f(n + 1) + 1;
      void main() {
        try { f(0); } on StackOverflowError { print('a'); }
        try { f(0); } on Error catch (e, s) { print('b'); truth(s == s); }
        try { f(0); } catch (e) { print('c'); } finally { print('d'); }
        print('f');
      }
    ''');
    shows('overflows while tries are open', '''
      int depth = 0, finals = 0;
      void f() { depth++; try { f(); } finally { finals++; } }
      void main() {
        try { f(); } on StackOverflowError { truth(depth - finals < 2); }
      }
    ''');
    shows('overflows are one object', '''
      int f(int n) => f(n + 1) + 1;
      Object? caught() { try { f(0); } catch (e) { return e; } return null; }
      void main() { truth(identical(caught(), caught())); }
    ''');
    shows('overflows end the program', '''
      int f(int n) => f(n + 1) + 1;
      void main() { print('a'); f(0); }
    ''');
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(translate(source), failsWith(['main.dart:$problem']));
    });

    const what = 'Not supported yet:';
    reports('void main() { throw 1; }', '1:21: $what using int as an object.');
    reports('void main() { throw "a"; }', '1:21: $what simple string literal.');
    reports(
      'void main() { throw Exception("a"); }',
      '1:21: $what calling Exception of the SDK.',
    );
    reports(
      'void main() { try {} on int catch (e) { } }',
      '1:25: $what catching int.',
    );
    reports(
      'void main() { try {} on String { } }',
      '1:25: $what catching String.',
    );
    reports(
      'class A<T> {}\nvoid main() { try {} on A<int> { } }',
      '2:25: $what catching A<int>.',
    );
    reports(
      'void main() { try {} on Error catch (e) { e.stackTrace; } }',
      '1:43: $what calling stackTrace of the SDK.',
    );
    reports(
      'void main() { try {} catch (e, s) { s.toString(); } }',
      '1:37: $what calling toString of the SDK.',
    );
    reports(
      'int n = 0;\nclass A { String toString() => "\$n"; }\nvoid main() { throw A(); }',
      '2:18: $what throwing an object with this toString.',
    );
    reports(
      'int n = 0;\nclass A { String toString() { n++; return "a"; } }\nvoid main() { throw A(); }',
      '2:18: $what throwing an object with this toString.',
    );
    reports(
      'class A extends ArgumentError {}\nvoid main() { A(); }',
      '1:7: $what extending ArgumentError of the SDK.',
    );
    reports(
      'class A { A? b; }\nvoid f(A? a) { a?.b!; }\nvoid main() { f(null); }',
      '2:16: $what null-aware chains.',
    );
    reports('void main() { 1.5.round(); }', '1:15: $what method invocation.');
  });

  test('objects that are never thrown may have any toString', () async {
    await translate('''
      int n = 0;
      class A { String toString() => "\$n"; }
      class B {}
      void main() { A(); throw B(); }
    ''');
  });
}
