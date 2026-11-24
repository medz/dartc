import 'package:dartc/driver.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';
import 'support.dart';

void main() {
  void shows(String name, String source) => agrees(name, '$tools\n$source');

  group('objects', () {
    shows('hold fields of every type', '''
      class P { int x = 3; double y = 2.5; bool z = true; P? next; }
      void main() {
        final p = P(), q = P();
        p.x = 8; p.next = q; q.y = -1; q.z = false; q.next = p;
        number(p.x); number(q.x); truth(p.y == 2.5); truth(q.y < 0);
        truth(p.z); truth(q.z); truth(p.next == q); truth(q.next == p);
        truth(p.next?.next == p); truth(p == q); truth(P().next == null);
      }''');
    shows('form lists and trees', '''
      class Node { final int value; Node? left, right; Node(this.value); }
      Node insert(Node? at, int value) {
        if (at == null) return Node(value);
        if (value < at.value) at.left = insert(at.left, value);
        else at.right = insert(at.right, value);
        return at;
      }
      void walk(Node? at) {
        if (at == null) return;
        walk(at.left); number(at.value); walk(at.right);
      }
      void main() {
        Node? root;
        var seed = 7;
        for (var i = 0; i < 40; i++) { seed = seed * 37 % 101; root = insert(root, seed); }
        walk(root);
      }''');
    shows('assignments to fields', '''
      class C { int n = 1; double d = 1; C? c; C get self { print('self'); return this; } }
      void main() {
        final c = C();
        number(c.n = 5); number(c.n += 2); number(c.n++); number(++c.n); number(c.n--);
        number(--c.n); c.n *= 3; c.n ~/= 2; number(c.n); c.d /= 4; truth(c.d == 0.25);
        c.self.n += 10; number(c.n); c.self.n++; number(c.n);
        c.c ??= C(); c.c ??= c; truth(c.c == c); final other = c.c ?? c; truth(other == c);
      }''');
  });

  group('constructors', () {
    shows('run in order', r'''
      class A {
        int a = trace(1); final int b; int c;
        A(this.b, {int x = 5}) : c = trace(x) { print('A'); show(); }
        void show() => print('A.show');
      }
      class B extends A {
        int d = trace(2); int e;
        B(int q, {super.x}) : e = trace(q), super(trace(q + 1)) { print('B'); }
        B.two() : this(trace(9));
        B.three(super.b) : e = 7;
        @override
        void show() { number(d); number(e); number(b); number(c); super.show(); }
      }
      void main() { B(7, x: 8); B.two(); B.three(4).show(); }''');
    shows('defaults and implicit ones', '''
      class A { int n = 3; }
      class B extends A {}
      class C { int a, b; C([this.a = 1, this.b = 2]); C.named({this.a = 3, required this.b}); }
      class D extends C { D([super.a, super.b]); D.n({super.a, required super.b}) : super.named(); }
      void show(C c) { number(c.a); number(c.b); }
      void main() {
        number(B().n); show(C()); show(C(7)); show(C(7, 8)); show(C.named(b: 4)); show(C.named(b: 5, a: 6));
        show(D()); show(D(9)); show(D.n(b: 1)); show(D.n(b: 1, a: 2));
      }''');
    shows(
      'factories',
      '''
      abstract class Shape {
        factory Shape(int sides) { if (sides == 4) return Square(2); return Other(); }
        factory Shape.big() => Square(9);
        int area();
      }
      class Square implements Shape { final int n; Square(this.n); @override int area() => n * n; }
      class Other implements Shape { @override int area() => 1; }
      void main() { number(Shape(4).area()); number(Shape(3).area()); number(Shape.big().area()); }''',
    );
    shows(
      'parameters and bodies',
      '''
      class C {
        int n;
        C(int n) : n = n * 2 { n += 100; this.n += n; number(n); if (n > 150) return; print('end'); }
        C.assign(int m) : n = 0 { n = m; }
      }
      void main() { number(C(3).n); number(C(60).n); number(C.assign(4).n); }''',
    );
  });

  group('methods', () {
    shows('are chosen by the object', r'''
      class A { int f(int x) => x + 1; int g(int x) => f(x) * 10; }
      class B extends A { @override int f(int x) => super.f(x) + 2; }
      class C extends B { @override int f(int x) => super.f(x) * super.g(1) ~/ 10; }
      void use(A a) { number(a.f(3)); number(a.g(3)); }
      void main() { use(A()); use(B()); }''');
    shows(
      'of interfaces and abstract classes',
      '''
      abstract class I { int f(int x); int get p; set p(int v); }
      abstract class Half implements I { @override int get p => 40; int both() => f(1) + p; }
      class J implements I { @override int p = 3; @override int f(int x, [int y = 10]) => x + y + p; }
      class K extends J { @override int f(int x, [int y = 20]) => super.f(x, y) * 2; @override int get p => super.p + 100; }
      class L extends Half { int stored = 0; @override int f(int x) => -x; @override set p(int v) { stored = v * 2; } }
      void use(I i) { i.p = 5; number(i.f(1)); number(i.p); i.p += 1; number(i.p); }
      void main() { use(J()); use(K()); final l = L(); use(l); number(l.stored); number(l.both()); }''',
    );
    shows('with optional and named parameters', '''
      class A { int f(int a, {int b = 1, int c = 2}) => a * 100 + b * 10 + c; }
      class B extends A { @override int f(int a, {int c = 7, int b = 8, int d = 9}) => super.f(a, b: b, c: c) + d * 1000; }
      class C implements A { @override int f(int z, {int b = 5, int c = 6}) => z - b - c; }
      void use(A a) {
        number(a.f(1)); number(a.f(1, b: 3)); number(a.f(1, c: 4)); number(a.f(1, c: 4, b: 3));
        number(a.f(trace(1), c: trace(2), b: trace(3)));
      }
      void main() { use(A()); use(B()); use(C()); number(B().f(1, d: 2)); }''');
    shows(
      'overriding void with a result',
      '''
      class A { void f() => print('A'); }
      class B extends A { @override int f() { print('B'); return 4; } }
      class C extends B { @override int f() => super.f() + 1; }
      void use(A a) => a.f();
      void main() { use(A()); use(B()); use(C()); number(B().f()); number(C().f()); }''',
    );
    shows(
      'with the same names in unrelated classes',
      '''
      class A { int f(int x) => x; int n = 1; }
      class B { double f(double x) => x; double n = 2.5; }
      class C { void f() => print('C'); bool n = true; }
      void main() { number(A().f(3)); truth(B().f(1.5) == 1.5); C().f(); number(A().n); truth(B().n > 2); truth(C().n); }''',
    );
    shows('getters and setters', '''
      class T { double c = 0; double get f => c * 1.8 + 32; set f(double v) => c = (v - 32) / 1.8; }
      class Counter { int _n = 0; int get next => ++_n; set _raw(int v) { _n = v; } void reset() { _raw = 10; } }
      void main() {
        final t = T(); t.f = 212; truth(t.c == 100); t.f += 18; truth(t.c == 110);
        final c = Counter(); number(c.next); number(c.next); c.reset(); number(c.next);
      }''');
    shows('static', '''
      class M { static int twice(int x) => x * 2; static const k = 7; int use() => twice(k) + M.twice(1); }
      void main() { number(M.twice(4)); number(M().use()); number(M.k); }''');
    shows('receivers are evaluated first', '''
      class C { int f(int a, int b) => a * 10 + b; C me(int n) { number(n); return this; } }
      void main() { number(C().me(1).f(trace(2), trace(3))); }''');
    shows('private names of each library', '''
      class A { int _f() => 1; int f() => _f(); }
      class B extends A { @override int _f() => 2; }
      void main() { number(A().f()); number(B().f()); }''');
  });

  group('corners', () {
    shows(
      'super equality of Object',
      '''
      class P { final int n; P(this.n); @override bool operator ==(Object o) { number(n); return super == o; } bool differs(P o) => super != o; }
      void main() { final p = P(1); truth(p == p); truth(p == P(2)); truth(p.differs(p)); truth(p.differs(P(3))); }''',
    );
    shows(
      'a field hides one of the superclass',
      '''
      class A { int x = 1; int a() => x; }
      class B extends A { @override int x = 2; int up() => super.x; void set() { super.x = 7; super.x += 2; super.x++; } }
      void main() { final b = B(); number(b.x); number(b.a()); number(b.up()); b.set(); number(b.x); number(b.up()); }''',
    );
    shows('abstract members and fields between', '''
      abstract class A { abstract int n; void f() => print('A'); int g(); }
      abstract class B extends A { @override void f(); @override int g() => n * 2; }
      class C extends B { @override int n = 4; }
      class D extends B { @override int get n => 6; @override set n(int v) => number(v); @override void f() { super.f(); print('D'); } }
      void use(A a) { a.f(); number(a.g()); a.n += 1; number(a.n); }
      void main() { use(C()); use(D()); }''');
    shows('a setter or getter overridden alone', '''
      class A { int x = 1; }
      class B extends A { @override set x(int v) { number(v); super.x = v * 2; } }
      class C extends B { @override int get x => super.x + 100; }
      void use(A a) { a.x = 5; number(a.x); a.x++; number(a.x); }
      void main() { use(A()); use(B()); use(C()); }''');
    shows(
      'super operators',
      '''
      class A { int operator [](int i) => i; void operator []=(int i, int v) { number(i); number(v); } A operator +(A o) { print('+'); return o; } bool operator <(A o) => true; }
      class B extends A {
        @override int operator [](int i) => super[i + 1] * 2;
        @override void operator []=(int i, int v) { super[i] = v + 1; super[i] += 3; }
        @override A operator +(A o) => super + o;
        void f() => truth(super < this);
      }
      void main() { final b = B(); number(b[3]); b[4] = 5; truth(b + b == b); b.f(); }''',
    );
    shows(
      'implicit super with defaults',
      '''
      class A { final int n; A([this.n = 3]); A.named({this.n = 4}); }
      class B extends A {}
      class C extends A { C(); C.named({super.n}) : super.named(); C.pos([super.n]); C.other([super.n = 9]); }
      void main() { number(B().n); number(C().n); number(C.named().n); number(C.named(n: 1).n); number(C.pos().n); number(C.pos(2).n); number(C.other().n); }''',
    );
    shows(
      'formals seen from initializers and bodies',
      '''
      class A { int x, y, z = 0; A(this.x) : y = x + 1 { x = 10; z = x + y; } }
      class B extends A { int w; B(super.x) : w = x * 100 { x++; } }
      void main() { final a = A(1); number(a.x); number(a.y); number(a.z); final b = B(2); number(b.w); number(b.x); }''',
    );
    shows('joins of objects', '''
      class A { int n; A(this.n); int f() => n; }
      class B extends A { B(super.n); @override int f() => n * 10; }
      A pick(bool b, A x, A y) => b ? x : y;
      void main() {
        A a = A(1), b = B(2); A? c;
        for (var i = 0; i < 4; i++) { final t = a; a = b; b = t; number(a.f()); if (i > 1) c = a; }
        if (c != null) number(c.f());
        number(pick(1 < 2, a, b).f()); number(pick(1 > 2, a, b).f());
      }''');
    shows(
      'many classes answer one call',
      '''
      abstract class S { int get k; int f(int a, [int b = 1]); }
      class A implements S { @override int k = 1; @override int f(int a, [int b = 2, int c = 3]) => a + b + c; }
      class B implements S { @override int get k => 2; @override int f(int a, [int b = 4]) => a * b; }
      class C extends B { @override int get k => super.k + 10; }
      class D extends A { @override int f(int a, [int b = 9, int c = 8]) => super.f(a, b) - c; }
      class E implements S { final S s; E(this.s); @override int get k => s.k * 2; @override int f(int a, [int b = 5]) => s.f(a, b) + s.f(a); }
      void use(S s) { number(s.k); number(s.f(3)); number(s.f(3, 6)); }
      void main() { use(A()); use(B()); use(C()); use(D()); use(E(D())); use(E(E(C()))); }''',
    );
    shows('objects that call themselves back', '''
      class Even { final Odd odd = Odd(); bool test(int n) => n == 0 || odd.test(n - 1, this); }
      class Odd { bool test(int n, Even e) => n != 0 && e.test(n - 1); }
      void main() { truth(Even().test(10)); truth(Even().test(7)); }''');
    shows('a const constructor without const', '''
      class P { final int x, y; const P(this.x, [this.y = 2]); P get flipped => P(y, x); }
      void main() { final p = P(1).flipped; number(p.x); number(p.y); }''');
    shows(
      'never returning methods',
      '''
      class A { Never stop(int n) { number(n); exit(n); } int f(bool b) => b ? 1 : stop(7); }
      void main() { final a = A(); number(a.f(true)); number(a.f(false)); print('no'); }''',
    );
    shows('null-aware chains of null-aware parts', '''
      class C { C? next; int n = 3; C? get self => this; }
      void main() {
        final c = C(); C? none; c.next = C();
        truth(c.next?.next?.next == null); truth(c.self?.next?.self == c.next); truth(none?.next?.self == null);
      }''');
  });

  group('operators', () {
    shows('of classes', '''
      class V {
        final int x; V(this.x);
        V operator +(V o) => V(x + o.x);
        V operator -(V o) => V(x - o.x);
        V operator -() => V(-x);
        V operator ~() => V(x * 100);
        bool operator <(V o) => x < o.x;
        int operator [](int i) => x + i;
        void operator []=(int i, int v) { number(i); number(v); }
      }
      void main() {
        final a = V(1); var b = V(5);
        number((a + b).x); number((a - b).x); number((-a).x); number((~a).x); truth(a < b);
        number(a[3]); a[trace(2)] = trace(9); a[2] += 5; a[1]++; number(a[4] = 6); number(++a[0]);
        b += a; number(b.x); b -= a; number(b.x);
      }''');
    shows('equality', '''
      class E {
        final int v; E(this.v);
        @override bool operator ==(Object o) { print('eq'); return identical(this, o) || v == 9; }
        @override int get hashCode => v;
      }
      class F extends E { F() : super(9); @override bool operator ==(Object o) => super == o; }
      class P {}
      void main() {
        E? n; final e = E(1), f = E(1), nine = E(9); P? p; final q = P();
        truth(n == null); truth(null == n); truth(n == e); truth(e == n); truth(e == e); truth(e == f); truth(e != f);
        truth(nine == f); truth(F() == e); truth(n != null); truth(p == q); truth(q == q); truth(q != p); truth(p == null);
        truth(identical(e, f)); truth(identical(e, e)); truth(identical(n, null)); Object o = e, r = q; truth(o == f); truth(r == q); truth(r == o);
        number(e.hashCode);
      }''');
  });

  group('null', () {
    shows('is tested and passed over', '''
      class C { C? next; int n = 1; C? f(int x) { number(x); return next; } void g() => print('g'); }
      void main() {
        C? a, b = C(); a?.g(); b.g(); a?.f(trace(5)); b.f(trace(6));
        C? c = b; if (1 < 2) c.next = C(); truth(a?.next == null); truth(c.next?.next == null);
        final d = a ?? b; truth(d == b); a ??= C(); truth(a == b); a ??= b; truth(a == b);
        if (c.next != null && b.next == null) print('no'); else print('yes');
        for (C? at = b; at != null; at = at.next) number(at.n);
      }''');
  });

  group('order', () {
    shows('of everything in one expression', '''
      class C {
        int n = 0;
        C get c { print('get'); return this; }
        set s(int v) { print('set'); number(v); }
        int get s { print('gets'); return 1; }
        int operator [](int i) { print('index'); return i; }
        void operator []=(int i, int v) { print('store'); number(i); number(v); }
      }
      C make(int n) { number(n); return C(); }
      void main() {
        make(1).c.s = trace(2);
        make(3).s += trace(4);
        make(5)[trace(6)] = trace(7);
        make(8).c[trace(9)] += trace(10);
        number(make(11)[trace(12)]++);
        number(make(13).s++);
        var x = 1; x = x + (x = 5) + x; number(x);
      }''');
  });

  test('only what can be reached is translated', () async {
    final module = await translate('''
      class A { void f() => print('A'); void unused() { [1]; } }
      class B extends A { @override void f() { [2]; } }
      class C { void f() { [3]; } }
      void main() { A().f(); if (1 > 2) other(null); }
      void other(C? c) => c?.f();
    ''');
    final names = module.classes.map((class_) => class_.name);
    expect(names, contains('A'));
    expect(names, isNot(anyOf(contains('B'), contains('C'))));
    expect((HirInterpreter(module)..run()).output, 'A\n');
  });

  test('members of other libraries and private names stay apart', () async {
    final directory = writeSources({
      'main.dart': '''
import 'a.dart';
class B extends A { int _f() => 2; int g() => _f(); }
void main() { if (B().f() == 1 && B().g() == 2 && make().n == 4) print('ok'); }''',
      'a.dart': '''
class A { int _f() => 1; int f() => _f(); int n = 4; }
A make() => A();''',
    });
    final program = await loadProgram(
      '${directory.path}/main.dart',
      sdk: await packagedSdk(),
    );
    final interpreter = HirInterpreter(translateProgram(program))..run();
    expect(interpreter.output, 'ok\n');
  });

  group('not supported yet:', () {
    void reports(String source, String problem) => test(problem, () async {
      await expectLater(translate(source), failsWith(['main.dart:$problem']));
    });

    const what = 'Not supported yet:';
    reports(
      'class A(int x) {}\nvoid main() { A(1); }',
      '1:7: $what primary constructors.',
    );
    reports(
      'class A(final int x);\nvoid main() { A(1); }',
      '1:7: $what primary constructors.',
    );
    reports(
      'class A { external void f(); }\nvoid main() { A().f(); }',
      '1:28: $what a function without a body.',
    );
    reports(
      'class A { external A(); }\nvoid main() { A(); }',
      '1:11: $what external constructors.',
    );
  });
}
