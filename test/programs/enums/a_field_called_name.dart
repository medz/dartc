enum C {
  a(7),
  b.other('x');

  const C(this._name);
  const C.other(String s) : _name = 8;
  final int _name;
  int get own => _name;
}

enum S {
  x('own'),
  y('other');

  const S(this._name);
  final String _name;
  String get own => _name;
}

mixin M {
  int get _name => 5;
  int get own => _name;
}

enum D with M { z }

enum I {
  q;

  int get _index => 3;
  int get own => _index;
}

void main() {
  print((C.a.own, C.a.name, C.a, C.a.index)); // expect: (7, a, C.a, 0)
  print((C.b.own, C.b.name, C.b, C.b.index)); // expect: (8, b, C.b, 1)
  print((S.x.own, S.x.name, S.y.own, S.y.name, S.y)); // expect: (own, x, other, y, S.y)
  print((D.z.own, D.z.name, D.z)); // expect: (5, z, D.z)
  print((I.q.own, I.q.index, I.q)); // expect: (3, 0, I.q)
  print(C.values.byName('b')); // expect: C.b
  print(C.values.map((c) => c._name)); // expect: (7, 8)
  const k = C.a;
  print((k == C.values.first, identical(k, C.a), k._name)); // expect: (true, true, 7)
  print(switch (C.b) {
    C.a => 'a',
    C.b => 'b',
  }); // expect: b
  print({C.a: 1, S.x: 2}[S.x]); // expect: 2
}
