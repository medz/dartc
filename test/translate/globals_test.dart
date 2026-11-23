import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';
import 'support.dart';

void main() {
  void shows(String name, String source) => agrees(name, '$tools\n$source');

  group('variables', () {
    shows('start with literals', '''
      int a = 3; int b = -4; double c = 2.5; double d = -1; bool e = true;
      class P { int n = 9; }
      P? p; P? q = null; final int z = 6; var v = 7;
      void main() {
        number(a); number(b); truth(c == 2.5); truth(d == -1.0); truth(e);
        truth(p == null); truth(q == null); number(z); number(v);
      }
    ''');
    shows('change', '''
      int a = 3; double d = 1.5; bool b = false;
      class P { int n = 9; }
      P? p;
      void change() { a = 5; d = -d; b = !b; p = P(); }
      void main() {
        change();
        number(a); truth(d == -1.5); truth(b); truth(p != null);
        p = null; truth(p == null);
        number(a = 8); number(a); number(a += 2); number(a++); number(++a);
        number(a--); number(a);
        P? x; number(p == null ? 1 : 0); x = p ??= P(); truth(x == p);
        final old = p; p ??= P(); truth(p == old);
      }
    ''');
    shows('are set before their first use, in order', '''
      int a = trace(1);
      int b = trace(2) + a;
      final int c = trace(3);
      int unused = trace(4);
      int n() { number(99); return 5; }
      void main() { print('main'); number(b); number(a); number(c); number(b); }
    ''');
    shows('are not set if they are assigned first', '''
      int a = trace(1), b = trace(2);
      void main() { a = 5; number(a); b += 10; number(b); b++; number(b); }
    ''');
    shows('may be assigned and read while they are set', '''
      int calls = 0;
      int a = first(); int first() { a = 7; return 3; }
      int b = second(); int second() => ++calls == 1 ? b + 1 : 5;
      void main() { number(a); number(b); number(calls); }
    ''');
    shows('hold objects made once', '''
      class P { int n; P(this.n) { number(n); } P? next; }
      final P one = P(1); P two = P(2);
      void main() {
        truth(one == one); two.next = one; two.n = 8;
        number(two.n); truth(two.next == one); two = P(3); number(two.n);
        two.next = two; truth(two.next!= one);
      }
    ''');
    shows('keep what a condition skips unset', '''
      bool yes = true;
      int a = trace(1);
      void main() {
        if (!yes) a;
        print('then'); truth(yes || a == 1); truth(!yes || a == 1);
      }
    ''');
    shows('of any type can be lazy', '''
      double d = half(3.0); double half(double x) => x / 2;
      bool b = not(true); bool not(bool x) => !x;
      class P {} P? make(bool b) => b ? P() : null;
      P? p = make(false), q = make(true);
      int calls = 0; P? none() { calls++; return null; } P? r = none();
      void main() {
        truth(d == 1.5); truth(b); truth(p == null); truth(q == q);
        truth(q == null); truth(r == null); truth(r == null); number(calls);
      }
    ''');
    shows('that never get a value end the program', '''
      int a = exit(4);
      void main() { print('a'); number(a); }
    ''');
    test('of other libraries', () async {
      final directory = writeSources({
        'main.dart': '''
import 'dart:io';
import 'a.dart' as a;
import 'a.dart' show A, x;
void main() {
  a.x = 3; a.A.s += x; a.A.s++;
  exit(a.A.s * 10 + A.s + a.k.n + a.get);
}''',
        'a.dart': '''
int x = 1;
class A { static int s = 2; final int n; const A(this.n); }
const k = A(100);
int get get => x;''',
      });
      final program = await loadProgram(
        '${directory.path}/main.dart',
        sdk: hostSdk,
      );
      expect(HirInterpreter(translateProgram(program)).run(), 169);
    });
  });

  group('static fields', () {
    shows('are like variables', '''
      class A {
        static int n = 3; static int m = trace(4);
        static final A one = A(); static A? none;
        int get() => n; void set(int v) { n = v; m = v + 1; }
        static int twice() => n * 2;
      }
      class B { static int n = 50; int f() => n; }
      void main() {
        number(A.n); A.n = 6; number(A().get()); A().set(8); number(A.n);
        number(A.m); number(A.twice()); A.n += 2; number(A.n++); number(A.n);
        truth(A.one == A.one); truth(A.none == null); A.none ??= A.one;
        truth(A.none == A.one); number(B.n); number(B().f());
      }
    ''');
    shows('are used by name inside their class', '''
      class A {
        static int n = 1;
        void up() { n++; this.other(); }
        void other() {}
      }
      class B extends A { void down() { A.n -= 5; } }
      void main() {
        final b = B(); b.up(); b.up(); b.down(); number(A.n);
      }
    ''');
  });

  group('getters and setters', () {
    shows('of libraries', '''
      int _x = 1;
      int get x { print('get'); return _x; }
      set x(int value) { print('set'); _x = value; }
      void main() {
        number(x); x = 5; number(x); x += 2; number(x++); number(++x);
        number(x = 4);
      }
    ''');
    shows('of classes', '''
      class A {
        static int _x = 1;
        static int get x { print('get'); return _x; }
        static set x(int value) { print('set'); _x = value; }
        static A? _a;
        static A? get a => _a;
        static set a(A? value) { _a = value; }
        int f() { x++; return x; }
      }
      void main() {
        number(A.x); A.x = 5; A.x--; number(A.x); number(A().f());
        truth(A.a == null); A.a ??= A(); truth(A.a == A.a);
      }
    ''');
  });

  group('constant objects', () {
    shows('hold their fields', '''
      class A {
        final int n; final double d; final bool b; final A? next;
        const A(this.n, this.d, this.b, [this.next]);
      }
      class B extends A {
        final int extra; final int more = 7;
        const B(int n) : extra = n + 1, super(n * 2, n / 2, n > 3);
        int sum() => n + extra + more;
      }
      const a = A(1, 2, true, B(5)), a0 = A(0, 0, false);
      A orZero(A? a) => a ?? a0;
      void main() {
        final b = orZero(a.next), c = orZero(b.next);
        number(a.n); truth(a.d == 2.0); truth(a.b); number(b.n); number(c.n);
        number(const B(5).sum()); truth(const B(5).d == 2.5);
        truth(const B(5).b); truth(const B(3).b);
      }
    ''');
    shows('and variables keep the sign of zero', '''
      class D { final double d; const D(this.d); }
      double a = -0, b = 0, c = -0.0, d = -1; const double e = -0;
      void negative(double d) { truth(1 / d < 0); }
      void main() {
        negative(a); negative(b); negative(c); negative(d); negative(e);
        negative(const D(-0).d); negative(const D(0).d); negative(const D(e).d);
        double x = -0; negative(x);
      }
    ''');
    shows('are the same if they are equal', '''
      class A { final int n; final A? next; const A(this.n, [this.next]); }
      class B extends A { const B(int n) : super(n); }
      class D { final double d; const D(this.d); }
      const k = A(1);
      class S { static const A one = A(1); }
      void main() {
        truth(identical(const A(1), k)); truth(identical(k, S.one));
        truth(identical(const A(1), const A(2)));
        truth(identical(const A(1), A(1))); truth(identical(const A(1), const B(1)));
        truth(identical(const A(1, A(2)), const A(1, A(2))));
        truth(identical(const A(1, A(2)), const A(1, B(2))));
        truth(identical(const D(0.0), const D(-0.0)));
        truth(identical(const D(0.0 / 0.0), const D(0.0 / 0.0)));
        truth(identical(const D(1), const D(1.0)));
        const local = A(1); truth(identical(local, k));
      }
    ''');
    shows('have members', '''
      class A {
        final int n; const A(this.n);
        int twice() => n * 2; int get more => n + 1;
        @override bool operator ==(Object other) => true;
        @override int get hashCode => 0;
      }
      abstract class Shape { const Shape(); int area(); }
      class Square extends Shape { final int side; const Square(this.side); int area() => side * side; }
      class Box implements Shape { const Box(); int area() => 1; }
      const Shape s = Square(4);
      int area(Shape shape) => shape.area();
      void main() {
        number(const A(3).twice()); number(const A(3).more);
        truth(const A(3) == const A(4));
        number(area(s)); number(area(const Box()));
      }
    ''');
    shows('are found by every way to write them', '''
      class A {
        final int n; const A(this.n);
        const A.other() : this(8);
        const factory A.made(int n) = A;
        static const A k = A(5);
      }
      const A x = A(1), y = x;
      const A? none = null;
      void main() {
        number(x.n); number(y.n); truth(identical(x, y));
        number(const A.other().n); number(A.k.n); truth(none == null);
        number((const A.made(6)).n); number((true ? const A(4) : x).n);
        const inner = A(9); number(inner.n);
      }
    ''');
    shows('are default values', '''
      class A { final int n; const A(this.n); }
      class B extends A { final A other; const B(super.n, {this.other = const A(3)}); }
      const k = A(4);
      int f([A a = const A(1), A? b, A c = k]) => a.n * 100 + (b ?? const A(2)).n * 10 + c.n;
      class M { int f({A a = const A(6)}) => a.n; }
      class N extends M { int f({A a = const A(7), A b = k}) => a.n + b.n; }
      int use(M m) => m.f();
      class P { final A a; P([this.a = const A(8)]); }
      class Q extends P { Q([super.a]); }
      class R extends Q { R([super.a = k]); }
      class T extends R { T([super.a]); }
      void main() {
        number(f()); number(f(const A(5))); number(f(k, k, k));
        number(B(1).other.n); number(const B(1).other.n);
        number(Q().a.n); number(R().a.n); number(T().a.n); number(use(M())); number(use(N()));
      }
    ''');
    shows('are values of variables', '''
      class A { final int n; const A(this.n); }
      const k = A(3);
      A a = const A(1); final A b = k; A? c = const A(2);
      class S { static A s = const A(1); }
      void main() {
        number(a.n); number(b.n); truth(identical(a, S.s)); truth(c != null);
        a = b; number(a.n); S.s = k; truth(identical(S.s, a));
      }
    ''');
    shows('run no code when the program does', '''
      class A { final int n; const A(this.n) : assert(n > 0); }
      const A k = A(1 + 2 * 3);
      const bool yes = identical(k, const A(7));
      void main() { number(k.n); truth(yes); }
    ''');
  });

  group('only what needs it', () {
    test('initializes lazily', () async {
      final module = await translate('''
        class A { const A(); }
        int a = 1; int b = -1; double c = 1; bool d = false;
        A? e; A f = const A(); const k = A(); A g = k; A h = A();
        void main() { a; b; c; d; e; f; g; h; }
      ''');
      expect(
        [for (final global in module.globals) global.name],
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'h is set'],
      );
      expect(
        [for (final function in module.functions) function.name],
        ['main', 'A.new', 'h', 'throw stackOverflow', 'report'],
      );
    });

    test('lists what the program uses', () async {
      final module = await translate('''
        class A { const A(); }
        int a = 1, unused = 2;
        const k = A();
        void main() { a; }
      ''');
      expect(module.globals.single.name, 'a');
      expect(module.classes, isEmpty);
    });
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(translate(source), failsWith(['main.dart:$problem']));
    });

    const what = 'Not supported yet:';
    reports(
      'late int x;\nvoid main() { x = 1; }',
      '1:10: $what late variables.',
    );
    reports(
      'class A { static late int x; }\nvoid main() { A.x = 1; }',
      '1:27: $what late variables.',
    );
    reports(
      'external int x;\nvoid main() { x; }',
      '1:14: $what external variables.',
    );
    reports(
      "import 'dart:io';\nvoid main() { exitCode; }",
      '2:15: $what simple identifier.',
    );
    reports(
      "import 'dart:io';\nvoid main() { exitCode = 1; }",
      '2:15: $what assignment to simple identifier.',
    );
    reports(
      'mixin M { static int n = 1; }\nvoid main() { M.n; }',
      '2:15: $what prefixed identifier.',
    );
    reports(
      'mixin M { static int n = 1; }\nvoid main() { M.n = 2; }',
      '2:15: $what assignment to prefixed identifier.',
    );
    reports(
      'class A { final String s; const A(this.s); }\nvoid main() { const A("a"); }',
      '1:24: $what a field of type String.',
    );
    reports(
      'class A { const A(); }\nvoid f(A a) { switch (a) { case const A(): } }\nvoid main() { f(A()); }',
      '2:39: $what this kind of case.',
    );
    reports(
      'class A { const A(); static const k = A(); }\nvoid f(A a) { switch (a) { case A.k: } }\nvoid main() { f(A()); }',
      '2:33: $what this kind of case.',
    );
  });
}
