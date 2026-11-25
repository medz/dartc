// Ways to give a field called `_name` a value.

const zero = 0.0;

enum A {
  a(1),
  b.twice(2),
  c.given(3, 4),
  d.named(name: 5),
  e.redirects(6),
  f.optional();

  const A(this._name);
  const A.twice(int n) : _name = n * 2;
  const A.given(int n, int m) : assert(m > 0), _name = n + m;
  const A.named({int name = 7}) : _name = name;
  const A.redirects(int n) : this(n + 1);
  const A.optional([this._name = 8]);
  final int _name, other = 10;
}

enum B {
  a,
  b;

  final String _name = 'B$zero', more = 'more';
}

enum C<T> {
  a<int>(1),
  b<String>('b');

  const C(this._name) : assert(_name != null);
  final T _name;
}

enum D {
  a(-0.0),
  b(0.0);

  const D(double d) : _name = d == 0.0 && d != 1.0;
  final bool _name;
}

enum E(final int _name) { a(1), b(2) }

enum F(final int _name) {
  a(1),
  b(2);

  int get twice => _name * 2;
}

enum G(this._name) {
  a(1);

  final int _name;
}

enum H(int n) {
  a(1);

  this : _name = n + 1;
  final int _name;
}

enum I(final int _name, [final int other = 2]) {
  a(1);

  this : assert(other > 1);
}

enum J {
  a;

  static const _name = 'static';
}

mixin M {
  int get _name => 1;
}

enum K with M { a }

class L {
  const L(this._name);
  final int _name;
}

void main() {
  for (final a in A.values) {
    print((a, a.name, a._name, a.other));
  }
  // expect: (A.a, a, 1, 10)
  // expect: (A.b, b, 4, 10)
  // expect: (A.c, c, 7, 10)
  // expect: (A.d, d, 5, 10)
  // expect: (A.e, e, 7, 10)
  // expect: (A.f, f, 8, 10)
  print([for (final b in B.values) (b._name, b.more, b)]); // expect: [(B0.0, more, B.a), (B0.0, more, B.b)]
  print([for (final c in C.values) (c._name, c.runtimeType, c)]); // expect: [(1, C<int>, C.a), (b, C<String>, C.b)]
  print([for (final d in D.values) (d._name, d)]); // expect: [(true, D.a), (true, D.b)]
  print([for (final e in E.values) (e._name, e)]); // expect: [(1, E.a), (2, E.b)]
  print([for (final f in F.values) (f._name, f.twice, f.name)]); // expect: [(1, 2, a), (2, 4, b)]
  print([for (final g in G.values) (g._name, g)]); // expect: [(1, G.a)]
  print([for (final h in H.values) (h._name, h)]); // expect: [(2, H.a)]
  print([for (final i in I.values) (i._name, i.other, i)]); // expect: [(1, 2, I.a)]
  print((J._name, J.a, K.a._name, K.a, const L(3)._name)); // expect: (static, J.a, 1, K.a, 3)
  print((A.a as dynamic)._name); // expect: 1
  const a = A.a, b = C.b;
  print((a._name, b._name)); // expect: (1, b)
  print(const {A.a: 1, A.b: 2}[A.b]); // expect: 2
}
