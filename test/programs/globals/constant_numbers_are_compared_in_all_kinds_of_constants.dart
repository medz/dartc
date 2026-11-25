class const P(final double a, {final bool z = -0.0 == 0.0}) {
  final bool w = -0.0 == 0.0;
  final bool q = 1.0 != 1;
  this : assert(a == 0.0, 'not zero');
}

class R {
  final bool e;
  const R(double a, double b) : e = a == b && identical(a, a);
  const R.of(Object? a, Object? b) : e = identical(a, b);
  factory R.f() => const R(0.0, -0.0);
}

extension type const X(double v) {
  static const same = 0.0 == -0.0;
}

@R(0.0, -0.0)
class S<T> {
  final bool e;
  const S(T a, T b) : e = a == b;
}

int calls = 0;
double next() {
  calls++;
  return 0.0;
}

class V {
  final bool a = next() == -0.0;
  bool get b => next() == -0.0;
}

void main() {
  print((
    const P(-0.0).z,
    const P(-0.0).w,
    const P(0.0).q,
    const R(0.0, -0.0).e,
    const R.of(1, 1.0).e,
    const R.of(double.nan, double.nan).e,
    const R.of(0.0, -0.0).e,
    const R.of('a', 'a').e,
    const R.of(null, 1.0).e,
    R.f().e,
    X.same,
  )); // expect: (true, true, false, true, false, true, false, true, false, true, true)
  print((
    const S<double>(0.0, -0.0).e,
    const S<num>(0, -0.0).e,
    const S<String>('a', 'a').e,
    const S<Object>(1, 'a').e,
    const S(double.nan, double.nan).e,
  )); // expect: (true, true, true, false, false)
  final v = V();
  print((v.a, v.b, calls)); // expect: (true, true, 2)
  const x = ((0.0 == -0.0) ? 2.5 : 1.0) == 2.5;
  print(x); // expect: true
  const l = <Object>[
    if (0.0 == -0.0) 'yes' else 'no',
    ...[0.0 == -0.0],
  ];
  print(l); // expect: [yes, true]
  if (1.0 case == 1 && == 1.0) print('rel'); // expect: rel
  print(switch (2.0) {
    const (0.0 == -0.0 ? 2.0 : 3.0) => 'c',
    _ => 'd',
  }); // expect: c
  final f = [(double a, [bool b = 0.0 == -0.0]) => b];
  print(f[0](1.0)); // expect: true
  const s = 'x' == 'y' || 1 == 2 || true == false || null == 0.0;
  print(s); // expect: false
  print(const P(1.0 - 1.0).a); // expect: 0.0
}
