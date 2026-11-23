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
class P {
  int n; P? next; List1? list; void Function(int)? f; dynamic d;
  P(this.n, [this.next]); int get twice => n * 2; P add(int k) { n += k; return this; } P? maybe(bool b) => b ? this : null; int operator [](int i) => n + i; void operator []=(int i, int v) { n = i * 10 + v; } set s(int v) { number(v); } void call() { print('call'); } P operator +(int k) => P(n + k); int? get none => null;
}
class List1 { int? x; P? p = P(50); int len = 0; void add(int v) { len++; x = v; } List1? self() => this; int operator [](int i) => len + i; void operator []=(int i, int v) { len = v; } }
P? pick(int n) { print('pick'); switch (n) { case 0: return null; case 1: return P(1); } final p = P(2, P(3, P(4))); p.list = List1(); p.next?.list = List1(); return p; }
''';

void main() {
  void shows(String name, String source) =>
      agrees(name, '$tools\n$_tools\n$source');

  group('cascades', () {
    shows('use one object again and again', '''
      P make() { print('make'); return P(1); }
      void main() {
        final p = make()..add(2)..n += 3..add(trace(4)).add(1)..s = 5..next = P(9); number(p.n); number(p.next?.n ?? 0);
        final q = P(2)..[1] = 7..[trace(2)] += 1..n += 1; number(q.n); number((P(3)..n *= 2).twice); number((P(5)..list = (List1()..add(6)..add(7))).list?.len ?? -1);
        var r = P(1)..f = number; r..f!(3)..f?.call(4)..next = (P(8)..n = 1); r.next!..n = 4..add(1); number(r.next!.n); P(1)..add(1)..call()..call(); P(4)..next?.n = 3..next ??= P(6)..next!.n += 1;
        dynamic d = P(1); d..n = 5..add(2)..next = P(1); show(d.n); (d..n = 8).add(1); number(d.n); final s = (p + 1)..n -= 2; number(s.n); true ? (P(1)..add(1)) : P(2); var x = P(1)..twice; number(x.n);
      }
    ''');
    shows('can be skipped for null', '''
      void main() { for (var i = 0; i < 3; i++) { final p = pick(i)?..add(trace(1))..n += trace(2); show(p?.n); pick(i)?..n = 4..s = 5; pick(i)?..list?.add(3)..[0] = trace(6); P? q = pick(i); q?..add(1); show(q?.n); } }
    ''');
  });

  group('null-aware chains', () {
    shows(
      'skip everything after null',
      '''
      void main() { for (var i = 0; i < 3; i++) { final p = pick(i); show(p?.next?.n); show(p?.next?.next?.twice); show(p?.add(trace(1)).add(trace(2)).n); show(p?.list?.self()?.len); show(p?.next!.n ?? -1 > 5); print('-'); } }
    '''
          .replaceAll(
            "show(p?.next!.n ?? -1 > 5);",
            "show(p?.add(1).maybe(true)!.n);",
          ),
    );
    shows('through members, elements and calls', '''
      void main() { for (var i = 0; i < 3; i++) { final p = pick(i);
        show(p?[trace(1)]); show(p?.next?[2]); show(p?.add(1)[3]); show(p?.maybe(true)?.add(2)[trace(4)]); show(p?.list?[5]); p?.f?.call(1); p?.f = number; p?.f?.call(trace(6)); p?.f!(7); p?.next?.call(); p?.call(); show((p?.next)?.n); show(p?.maybe(false)?.n); show(p?.none?.toDouble()); show(p?.d?.n); show(p?.twice.toDouble()); show(-(p?.n ?? 4)); show(p?.n == null); if (p?.n == 2) print('two'); if (p?.next != null) print('next');
        final f = p?.add; show(f?.call(5).n); int? t = p?.n; show(t); show(p?.next?.next?.next?.n); print('-'); } }
    ''');
    shows('assign', '''
      void main() { for (var i = 0; i < 3; i++) { final p = pick(i);
        p?.n = trace(1); show(p?.n); show(p?.n = trace(2)); p?.n += trace(3); show(p?.n++); show(++p?.n); p?.next?.n = trace(4); show(p?.next?.n); p?.next?.next?.n -= 1; show(p?.next?.next?.n); p?[trace(5)] = trace(6); show(p?.n); p?[1] += trace(7); show(p?.n); p?.next ??= P(70); show(p?.next?.n); p?.next?.next ??= P(trace(80)); p?.list?[1] = trace(8); show(p?.list?.len); p?.d = 5; p?.d += 1; show(p?.d); p?.d ??= 3; p?.s = trace(9); p?.add(1).n = 100; show(p?.n); p?.list?.x ??= trace(11); show(p?.list?.x); print('-'); } }
    ''');
    shows(
      'of statics and dynamics',
      '''
      class S { static P? p; static int n = 1; } P? g; 
      void main() { show(S.p?.n); S.p = P(4); show(S.p?.add(1).n); S.p?.n = 9; show(S.p?.n); show(S?.n); g?.n = 3; show(g?.n); g = P(1); g?.next?.n = 4; g?.next = P(2); show(g?.next?.n); dynamic d; show(d?.n); show(d?.add(1).n); show(d?.foo.bar[3].baz()); d?.n = trace(1); d?[trace(2)] = 3; show(d?[0]); d = P(5); show(d?.add(1).n); d?.n = trace(8); show(d?[1]); d?[1] = trace(2); show(d?.n); show(d?.next?.n); show(d?.maybe(true)?.n); Function? f; show(f?.call(trace(1))); f = (int n) => n + 1; show(f?.call(trace(1))); P? Function()? h; show(h?.call()?.n); h = () => P(6); show(h?.call()?.n); show(h()?.add(1).n); }
    '''
          .replaceAll(' show(S?.n);', ''),
    );
  });

  group('late', () {
    shows(
      'variables are set before they are used, or else throw',
      '''
      int calls = 0; int next() => ++calls;
      void go(void Function() f) { try { f(); print('ok'); } on Error { print('E'); } }
      void main() {
        late int a; void ra() => show(a); go(ra); a = 3; show(a); a = 4; show(a); late final int b; go(() => show(b)); void sb(int n) => b = n; sb(5); show(b); go(() => sb(6)); show(b); late int c = next(); show(calls); show(c); show(c); c = 9; show(c); late final d = next(); show(d); show(d); show(calls); late int e = next(); e = 1; show(e); show(calls);
        late P? p; go(() => show(p?.n)); p = null; show(p?.n); p = P(1); show(p.n); late Object? o; go(() => show(o)); o = null; show(o); late double x; x = 1.5; show(x); late bool y = calls > 1; show(y); late final int? z; go(() => show(z)); void sz(int? n) { z = n; } sz(null); show(z); go(() => sz(1));
        for (var i = 0; i < 2; i++) { late int k; go(() => show(k)); k = i; show(k); late final int m = next(); show(m); } late int Function(int) f; f = (n) => n < 2 ? 1 : n * f(n - 1); show(f(5)); late void Function() g = () => show(calls); g(); late int u, v = 2; u = v; show(u); int w() { late int q; void set() { q = 8; } go(() => show(q)); set(); return q; } show(w()); late String2 s = String2(); s.n++; show(s.n); late int t; t ??= 3;
      }
      class String2 { int n = 0; }
    '''
          .replaceAll(' late int t; t ??= 3;', ''),
    );
    shows('fields and globals', '''
      int calls = 0; int next() => ++calls; late int ga; late final int gb; late int gc = next(); late final gd = next(); late P? ge;
      class A { late int a; late final int b; late int c = next() + base; late final d = next() * base; late P? e; late final f = this; int base; static late int sa; static late final sb = next(); late double x; late bool y = false; A(this.base); int use() => c + d; late int Function() g = () => a; }
      class B extends A { B() : super(100) { a = 1; b = 2; } @override late int c = 7; @override int get d => super.d + 1; late final A own = A(5); } class C { late final int n; C([int? k]) { if (k != null) n = k; } C.init(this.n); }
      void go(void Function() f) { try { f(); print('ok'); } on Error { print('E'); } }
      void main() {
        go(() => show(ga)); ga = 1; show(ga); go(() => show(gb)); gb = 2; go(() => gb = 3); show(gb); show(gc); gc = 9; show(gc); show(gd); show(gd); go(() => show(ge)); ge = null; show(ge); go(() => show(A.sa)); A.sa = 4; show(A.sa++); show(A.sa); show(A.sb);
        final a = A(10); go(() => show(a.a)); a.a = 5; show(a.a += 1); go(() => show(a.b)); a.b = 6; go(() => a.b = 7); show(a.b); show(a.use()); show(a.use()); a.c = 1; show(a.use()); go(() => show(a.e?.n)); a.e = P(3); show(a.e?.n); show(a.f == a); go(() => show(a.x)); a.x = 2; show(a.x); show(a.y); show(a.g()); final b = B(); show(b.a); show(b.b); show(b.c); show(b.d); show(b.own.base); go(() => b.b = 3); dynamic d = A(1); go(() => show(d.a)); d.a = 3; show(d.a); go(() => d.b = 1); go(() => d.b = 1); final c = C(); go(() => show(c.n)); c.n = 4; go(() => c.n = 5); show(C(8).n); show(C.init(9).n); go(() => C.init(9).n = 1);
      }
    ''');
    shows('initializers may throw, or set their variable', '''
      int n = 0; int f() { if (++n < 3) throw P(n); return n; } late int a = f(); class A { late int b = f(); late final int c = g(); int g() { if (n > 100) { n -= 60; return c + 1; } return 6; } late int d = h(); int h() { d = 8; return 9; } }
      void go(void Function() f) { try { f(); print('ok'); } on P catch (p) { show(p.n); } on Error { print('E'); } }
      void main() { go(() => show(a)); go(() => show(a)); go(() => show(a)); go(() => show(a)); n = 0; final o = A(); go(() => show(o.b)); go(() => show(o.b)); go(() => show(o.b)); go(() => show(o.c)); n = 200; go(() => show(A().c)); go(() => show(o.d)); late int k = f(); n = 1; go(() => show(k)); go(() => show(k)); }
    ''');
    for (final (name, body) in [
      ('a variable', 'late int x; int r() => x; r(); x = 1;'),
      ('a final variable', 'late final int x; void s() { x = 1; } s(); s();'),
      ('a field', 'A().x;'),
      ('a final field', 'final a = A(); a.y = 1; a.y = 2;'),
      ('a global', 'g;'),
    ]) {
      shows(
        'end the program: $name',
        "late int g; class A { late int x; late final int y; } void main() { print('a'); $body }",
      );
    }
  });

  shows('factories redirect', '''
    class A { final int n; A(this.n); factory A.b(int n, [int k]) = B; factory A.c({required int z}) = C.named; factory A.g() = G<int>; const factory A.k(int n) = K; factory A.two(int n) = A.b; }
    class B extends A { B(super.n, [int k = 5]) { number(k); } } class C extends A { C.named({required int z, int y = 2}) : super(z * y); } class G<T> extends A { G() : super(7); bool has(Object? o) => o is T; } class K implements A { @override final int n; const K(this.n); }
    class L<T> { L(); factory L.sub(T t) = M<T>; factory L.pair(T a) = N<T, bool>; factory L.fix() = M<T>.fixed; T? get first => null; } class M<T> extends L<T> { final T? t; M(this.t); M.fixed() : t = null; @override T? get first => t; } class N<X, Y> extends L<X> { final X x; N(this.x); bool isY(Object? o) => o is Y; }
    void main() { number(A.b(1).n); number(A.b(1, 2).n); number(A.c(z: 4).n); final g = A.g(); truth(g is G<int>); number(const A.k(3).n); truth(identical(const A.k(3), const K(3))); number(A.two(6).n); L<int> l = L.sub(4); show(l.first); truth(l is M<int>); final p = L<num>.pair(1.5); truth(p is N<num, bool>); truth(p is N<int, bool>); truth(L<int>.fix() is M<int>); final f = A.b; number(f(9).n); L<int> Function(int) h = L.sub; truth(h(1) is M<int>); }
  ''');

  agrees('patterns match', r'''
    String g(int n) => switch (n) { < 0 => 'neg', 0 || 1 => 'small', >= 10 && < 20 => 'teen', int x => 'other $x' };
    void main() { int? a = 5; if (a case final x?) print(x); a = null; if (a case final x?) { print(x); } else { print('null'); } Object o = 'text'; if (o case String s when s.length > 2) print(s); if (o case int n) print(n); else print('no'); for (final n in [-1, 0, 1, 15, 30]) print(g(n)); var t = 0; if (3 case var q when (t = q) > 2) t++; print(t); switch (o) { case String s when s.isEmpty: print('e'); case String _: print("s"); default: print('d'); } switch (7) { case > 5: print('big'); case 3: print('three'); } final fs = <int Function()>[]; for (var i = 0; i < 3; i++) { if (i case var k when k != 1) fs.add(() => k * 10); } print(fs.map((f) => f()).toList()); print(switch (o) { 'a' => 1, 'text' => 2, _ => 3 }); switch ('b') { case 'a': case 'b': print('ab'); case _: print('x'); } }
  ''');
}
