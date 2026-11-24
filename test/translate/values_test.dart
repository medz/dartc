import 'package:test/test.dart';

import 'support.dart';

const _classes = r'''
class A { final int n; A(this.n); }
class B extends A { B(super.n); }
abstract class I {}
class C implements I { const C(); }
int zero() => 0;
bool yes() => zero() == 0;
/// Says what any object is.
void show(Object? o) {
  if (o == null) { print('null'); }
  else if (o is int) { number(o); }
  else if (o is double) { print('double'); number((o * 2).toInt()); }
  else if (o is bool) { truth(o); }
  else if (o is B) { print('B'); number(o.n); }
  else if (o is A) { print('A'); number(o.n); }
  else { print('other'); }
}
Object? pick(int n) {
  switch (n) {
    case 0: return 7; case 1: return 2.5; case 2: return true;
    case 3: return A(3); case 4: return B(4); case 5: return null;
    case 6: return C(); case 7: return -0.0; case 8: return false;
    case 9: return 0 / 0;
  }
  return 1 << 62;
}
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_classes\n$source');

  group('any object', () {
    shows('can be a number', '''
      Object field = 5;
      class P { Object o = 1; Object? p; P(this.p); Object get g => 2.5; set g(Object? v) { p = v; } }
      Object same(Object o) => o;
      Object? maybe([Object? o = 8]) => o;
      void main() {
        show(1); show(2.5); show(true); show(null); show(A(4));
        for (var i = 0; i < 11; i++) show(pick(i));
        show(same(3)); show(field); field = false; show(field);
        final p = P(6); show(p.o); show(p.p); show(p.g); p.g = 9; show(p.p); p.o = 3.5; show(p.o);
        show(maybe()); show(maybe(null)); show(maybe(true));
        Object o = yes() ? 1 : A(2); show(o); o = 1.5; show(o); show(o = 4);
        Object x = 1; number((x = 5) + 2); show(x);
      }
    ''');
    shows('compares numbers by value', '''
      void main() {
        for (var i = 0; i < 11; i++) {
          for (var j = 0; j < 11; j++) {
            final a = pick(i), b = pick(j);
            truth(a == b); truth(a != b); truth(identical(a, b));
          }
          final o = pick(i);
          truth(o == 7); truth(7 == o); truth(o == 2.5); truth(2.5 == o);
          truth(o == true); truth(o != null); truth(identical(o, 7)); truth(0.0 == o);
        }
        Object a = 7, b = 7.0; truth(a == b); truth(b == a); truth(identical(a, b));
        truth(identical(0.0, -0.0)); truth(identical(0 / 0, 0 / 0)); truth(identical(1, 1));
        truth(identical(true, yes())); truth(identical(a, 3 + 4)); truth(1 == 1.0);
        Object c = 9007199254740993, d = 9007199254740992.0; truth(c == d);
        num n = 3, m = 3.0; truth(n == m); truth(identical(n, m)); truth(n == 3); truth(a == 7.0);
      }
    ''');
    shows('can be a constant number', '''
      const Object i = 5, d = 2.5, b = true; const Object? n = null; const num m = 4; const int? k = 6;
      class K { final Object o; final num? n; const K(this.o, [this.n]); }
      void f([Object o = 3, num n = 2.5, int? i = 7, Object? z]) { show(o); show(n); show(i); show(z); }
      Object g = 1; num h = -2; double? j = -0; final Object l = false;
      void main() {
        show(i); show(d); show(b); show(n); show(m); show(k);
        show(const K(1).o); show(const K(1.5, 3).n); show(const K(true).n);
        truth(identical(const K(1), const K(1))); truth(identical(const K(1), const K(1.0)));
        truth(identical(const K(0.0), const K(-0.0)));
        f(); f(A(1), 1); show(g); show(h); show(l); truth(1 / (j ?? 1) < 0);
        truth(identical(i, 5)); truth(const K(true).o == true);
      }
    ''');
  });

  group('nullable numbers', () {
    shows('are numbers or null', '''
      int? a; double? b = 1.5; bool? c;
      class P { int? n; double? d; bool? b; P([this.n]); }
      int? f(int n) => n > 1 ? n : null;
      int orElse(int? n) => n ?? -1;
      void main() {
        show(a); show(b); show(c); a = 3; b = null; c = true; show(a); show(b); show(c);
        show(f(0)); show(f(5)); number(orElse(f(1))); number(orElse(f(2)));
        final p = P(); show(p.n); p.n = 4; p.n ??= 5; show(p.n); p.d ??= 2.5; show(p.d); show(p.b);
        int? x = f(7); if (x != null) { number(x + 1); x++; number(x); }
        x ??= 2; number(x); x = null; number(x ?? 9); x ??= 3; number(x + 1);
        number(f(4)!); try { number(f(0)!); } on TypeError { print('null'); }
        truth(f(0) == null); truth(f(3) == 3); truth(f(3) == 3.0); truth(f(0) == 0); truth(null == f(0));
        double? y = yes() ? 2.5 : null; if (y is double) truth(y > 2); truth((y ?? 0) > 1);
        bool? z = c; if (z == true) print('true'); if (z!) print('z');
        int? w; w = w == null ? 1 : w + 1; number(w); number(P(3).n ?? 0); number((P().n ?? 6) + 1);
        P? q = yes() ? P(8) : null; number(q?.n ?? 0); q = null; show(q?.n); show(q?.b);
      }
    ''');
    shows('are assigned through null-aware steps', '''
      int? n; int calls = 0; int next() => ++calls;
      void main() {
        number(n ??= next()); number(n ??= next()); number(calls); n = null;
        final int? r = (n ??= null); show(r); Object? o; show(o ??= 5); show(o ??= 6);
        num? m; m ??= 2; m = m + 1; show(m);
      }
    ''');
  });

  group('num', () {
    shows(
      'has the operators of its values',
      '''
      num pickNum(int n) => n == 0 ? 7 : n == 1 ? 2.5 : n == 2 ? -3 : -0.5;
      void main() {
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            final a = pickNum(i), b = pickNum(j);
            show(a + b); show(a - b); show(a * b); show(a / b); show(a ~/ b); show(a % b);
            truth(a < b); truth(a <= b); truth(a > b); truth(a >= b); truth(a == b); truth(a != b);
            var c = a; c += b; show(c); c -= 1; show(c); c *= 2; show(c); c++; show(c); --c; show(c);
          }
          final a = pickNum(i);
          show(-a); show(a + 1); show(1 + a); show(1.5 + a); show(a * 0.5); show(3 - a); show(2.0 < a ? 1 : 2);
          show(a.toInt()); show(a.toDouble()); int k = 5; show(k + a); double d = 1.5; d += a; show(d); d = d * a; show(d);
          show(k / a); show(k ~/ a); show(k % a); truth(k > a); truth(d <= a); truth(k == a);
        }
        num x = 1; x = x is int ? x + 1 : x; show(x); if (x is int) number(x << 2);
        num sum = 0; for (var i = 0; i < 5; i++) { sum += i.isEven2 ? i : i / 2; } show(sum);
      }
      extension on int { bool get isEven2 => this % 2 == 0; }
    '''
          .replaceAll('i.isEven2', 'i % 2 == 0')
          .replaceAll(
            '      extension on int { bool get isEven2 => this % 2 == 0; }\n',
            '',
          ),
    );
    shows('throws as its values do', '''
      num z = 0, o = 1, nan = 0 / 0;
      void main() {
        try { o ~/ z; } on IntegerDivisionByZeroException { print('a'); }
        try { o % z; } on UnsupportedError { print('b'); }
        try { o ~/ (z + 0.0); } on UnsupportedError { print('c'); }
        try { nan.toInt(); } on UnsupportedError { print('d'); }
        show(o / z > 100);
      }
    ''');
  });

  group('is and as', () {
    shows(
      'tell every kind of object',
      '''
      void main() {
        for (var i = 0; i < 11; i++) {
          final o = pick(i);
          truth(o is int); truth(o is double); truth(o is num); truth(o is bool); truth(o is A);
          truth(o is B); truth(o is I); truth(o is C); truth(o is Object); truth(o is Object?);
          truth(o is int?); truth(o is A?); truth(o is Null); truth(o is dynamic); truth(o is! num);
          truth(o is! A?); truth(o is Never); truth(o is Error);
        }
        truth(1 is int); truth(1 is num); truth(1 is double); truth(1.5 is Object); truth(1 is A);
        truth(trace(5) is int); A a = B(1); truth(a is B); truth(a is! I);
      }
    '''
          .replaceAll(' truth(o is Never);', ''),
    );
    shows('narrow variables', '''
      int size(Object? o) {
        if (o is int) return o + 1;
        if (o is! A) return -1;
        return o.n;
      }
      int both(Object a, Object b) => a is int && b is int ? a * b : a is A && b is A ? a.n + b.n : 0;
      void main() {
        for (var i = 0; i < 6; i++) number(size(pick(i)));
        number(both(3, 4)); number(both(A(5), B(6))); number(both(1, A(1)));
        Object o = 1; while (o is int) { if (o > 5) { o = A(o); } else { o = o + 2; } } show(o);
        num n = 3; if (n is double) { print('no'); } else { n as int; number(n << 1); }
      }
    ''');
    shows('narrow variables to null', '''
      void main() {
        int? n = yes() ? null : 5;
        if (n is! num) { truth(n == null); truth(A(1) != n); show(n); final m = n; show(m); }
        Object? o = n; while (o is! Object) { truth(o == n); o = 3; } show(o);
      }
    ''');
    shows('cast, or throw', '''
      void t(int n) {
        final o = pick(n);
        try { number(o as int); } on TypeError { print('no int'); }
        try { show(o as num?); } on TypeError { print('no num?'); }
        try { number((o as A).n); } on TypeError { print('no A'); }
        try { show(o as B?); } on TypeError { print('no B?'); }
        try { truth(o as bool); } on TypeError { print('no bool'); }
        try { show(o as Object); } on TypeError { print('no Object'); }
        try { show((o as double) + 1); } on TypeError { print('no double'); }
      }
      void main() {
        for (var i = 0; i < 7; i++) t(i);
        show(1 as num); show(1 as Object); try { show((1 as dynamic) as double); } on TypeError { print('no'); }
      }
    ''');
    for (final (name, body) in [
      ('a number', 'pick(0) as A;'),
      ('null', 'pick(5) as A;'),
      ('an object', 'pick(3) as int?;'),
      ('a double', 'pick(1) as int;'),
      ('a bool', 'pick(2) as num;'),
      ('dynamic', 'dynamic d = A(1); int x = d; number(x);'),
      ('a condition', 'dynamic d = 1; if (d) print("no");'),
      ('an argument', 'dynamic d = true; number(d);'),
      ('a covariant argument', 'A a = Q(1); a.up(A(2));'),
      ('a covariant field', 'P p = R(); p.f = A(1);'),
    ]) {
      shows(
        'end the program with $name',
        '''
        extension on A { void up(A a) {} }
        class Q extends A { Q(super.n); }
        class P { A? f; } class R extends P { @override covariant B? f; }
        class S { void up(covariant A a) {} } class T extends S { @override void up(B b) {} }
        void main() { print('a'); $body }
      '''
            .replaceAll('extension on A { void up(A a) {} }', '')
            .replaceAll('A a = Q(1); a.up(A(2));', 'S s = T(); s.up(A(2));'),
      );
    }
  });

  group('dynamic values', () {
    shows(
      'are checked where they get a type',
      '''
      dynamic f(int n) => pick(n);
      dynamic nothing() {}
      dynamic g = 5; int h = g; class P { dynamic d; int n = f(0); P([this.d]); }
      int ret(int n) => f(n);
      void take(int n, [double d = 1]) { number(n); truth(d > 1); }
      Object? top(dynamic d) => d;
      void main() {
        show(nothing()); show(g); number(h); g = 2.5; show(g); int x = f(0); number(x); number(ret(0));
        take(f(0), f(1)); try { take(f(1)); } on TypeError { print('a'); } try { ret(3); } on TypeError { print('b'); }
        try { x = f(1); } on TypeError { number(x); } try { int? y = f(5); show(y); y = f(2); } on TypeError { print('c'); }
        final p = P(); show(p.d); p.d = A(3); show(p.d); p.d = 4; number(p.n); show(top(p.d)); A a = P(A(9)).d; number(a.n);
        dynamic d = 1; d = true; if (d) print('yes'); bool b = d; truth(b); d = null; truth(d == null);
        truth(d is Null); d = B(6); if (d is A) number(d.n); truth(d == d); show(d as A); d ??= 4; show(d);
        Object o = f(3); show(o); try { o = f(5); } on TypeError { print('d'); } var v = f(0); show(v); v = 'a' == 'b';
      }
    '''
          .replaceAll(" v = 'a' == 'b';", ' v = false; show(v);'),
    );
    shows('are results of functions', '''
      class P { dynamic f() => 1; dynamic get g => 2.5; void h() {} dynamic operator [](dynamic i) => i; }
      class Q extends P { @override int f() => 2; @override A get g => A(3); @override dynamic h() => 7; @override int operator [](Object? i) => 5; }
      void use(P p) { show(p.f()); show(p.g); p.h(); show(p[4]); }
      void main() { use(P()); use(Q()); number(Q().f()); show(Q()[null]); if (yes()) return; }
    ''');
  });

  group('overriding', () {
    shows('with numbers', '''
      class P {
        Object f(int n) => n; Object? g; Object get h => 1.5; num k(double d) => d; void w(int n) { number(n); }
        Object? z(A a) => a; num i = 1; bool operator <(A a) => false;
      }
      class Q extends P {
        @override int f(Object n) { show(n); return 8; } @override double get h => 2.5; @override int k(num d) => 3;
        @override void w(num n) { show(n); } @override int? z(Object? a) => a is int ? a : null;
      }
      class R implements P {
        @override A f(num n) => A(n is int ? n : 0); @override Object? g = 4; @override int h = 6; @override double k(Object? d) => 2.5;
        @override void w(Object? n, [int m = 3]) { show(n); number(m); } @override B? z(A? a) => null; @override num i = 2.5;
        @override bool operator <(Object o) => true;
      }
      void use(P p) {
        show(p.f(5)); show(p.g); p.g = 3; show(p.g); show(p.h); show(p.k(0.5)); p.w(4); show(p.z(A(1)));
        show(p.i); p.i = 7; show(p.i); p.i++; show(p.i); truth(p < A(1));
      }
      void main() { use(P()); use(Q()); use(R()); number(Q().f(1.5)); truth(Q().h > 2); number(R().h); }
    ''');
    shows('with narrower parameters', '''
      class P { void f(covariant A a, [covariant Object o = 1]) { print('P'); } covariant A x = A(1); num y = 1; }
      class Q extends P { @override void f(B b, [int n = 2]) { print('Q'); number(b.n + n); } @override B x = B(2); @override covariant int y = 5; }
      void t(P p, A a, Object o, num n) {
        try { p.f(a, o); } on TypeError { print('a'); } try { p.f(a); } on TypeError { print('b'); }
        try { p.x = a; number(p.x.n); } on TypeError { print('c'); } try { p.y = n; show(p.y); } on TypeError { print('d'); }
      }
      void main() {
        t(P(), A(3), 4, 1.5); t(Q(), B(5), 6, 7); t(Q(), B(5), 1.5, 2.5); t(Q(), A(5), 6, 7);
      }
    ''');
  });

  group('thrown', () {
    shows('numbers', '''
      void t(int n) {
        try { final o = pick(n); if (o != null) throw o; } on int catch (e) { number(e + 1); }
        on num catch (e) { show(e + 1); } on bool catch (e) { truth(e); } on A catch (e) { number(e.n); }
        catch (e) { show(e); }
      }
      void main() { for (var i = 0; i < 9; i++) t(i); try { throw 5; } on double { print('no'); } catch (e) { show(e); } throw -42; }
    ''');
    shows(
      'a bool ends the program',
      "void main() { print('a'); throw yes(); }",
    );
  });

  shows('values that may end early', '''
    A? f(int n) { if (n > 0) return A(n); }
    Object? g(bool b) { if (b) return 1; }
    int? h(int n) { while (n < 10) { n++; } }
    dynamic k(bool b) { if (b) return true; }
    void main() { truth(f(0) == null); number(f(2)!.n); show(g(true)); show(g(false)); show(h(3)); show(k(true)); show(k(false)); }
  ''');

  agrees('numbers are no other numbers', r'''
      void main() { double d = 1.5;
              Object? r;
              try { r = d as int;
              } catch (e) { print(e);
              } try { r = true as int;
              } catch (e) { print(e);
              } try { r = 1 as double;
              } catch (e) { print(e);
              } print(r);
              if (d case int i) print(i);
              print(d is int);
              print(1 is double);
              int n = 1;
              try { print((n as double) + 1);
              } catch (e) { print(e);
              } print(switch (n) { double x => x, _ => 'n' });
              print(switch (true) { int() => 1, String s => s, bool b => b });
              if (n case double() && > 3) print('q');
              print(switch (2.5) { int(isEven: true) => 'e', num(sign: var s) => s });
              final (a, b) = (1, 2.0);
              if ((a, b) case (double x, int y)) print((x, y));
              else print('no');
              if ([1.5] case [int x]) print(x);
              }
  ''');
}
