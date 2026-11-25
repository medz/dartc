class C {
  final bool z, n;
  final double v;
  const C(double a) : v = a, z = a == 0.0, n = a != 0;
  const C.o(Object a) : v = 0.0, z = a == 0.0, n = a != 0;
  const C.q(double? a) : v = 0.0, z = a == 0.0, n = a != 0;
}

class D {
  final double a;
  const D(this.a);
  bool get eq => a == 0.0;
  static const list = [
    0.0 == -0.0,
    -0.0 == 0,
    0 == -0.0,
    0.0 != -0.0,
    double.nan == double.nan,
    double.nan != double.nan,
  ];
}

enum E {
  x(-0.0 == 0.0),
  y(1.5 == 1.5);

  final bool v;
  const E(this.v);
}

const num n1 = 0.0, n2 = -0.0;
const Object o1 = 0.0, o2 = -0.0;
const double? q1 = 0.0, q2 = -0.0;
const dynamic d1 = 0.0, d2 = -0.0;
const z = -0.0;
void def([bool b = z == 0.0, int c = z == 0.0 ? 1 : 2]) => print((b, c));
void main() {
  print(D.list); // expect: [true, true, true, false, false, true]
  print((
    const C(-0.0).z,
    const C(-0.0).n,
    const C(1).z,
    const C.o(-0.0).z,
    const C.o(-0.0).n,
    const C.q(-0.0).z,
    const C.q(-0.0).n,
    const C.q(null).z,
  )); // expect: (true, false, false, true, false, true, false, false)
  print(E.values.map((e) => e.v).toList()); // expect: [true, true]
  const r = [n1 == n2, o1 == o2, q1 == q2, d1 == d2, n1 != n2, o1 != o2];
  print(r); // expect: [true, true, true, true, false, false]
  const i = [
    identical(0.0, -0.0),
    identical(double.nan, double.nan),
    identical(1, 1.0),
    identical(n1, n2),
    identical(1.0, 1),
    identical(z, -0.0),
  ];
  print(i); // expect: [false, true, false, false, false, true]
  def(); // expect: (true, 1)
  print(switch (-0.0) {
    0.0 => 'zero',
    _ => 'other',
  }); // expect: zero
  print(switch (0) {
    0.0 => 'zero',
    _ => 'other',
  }); // expect: zero
  print(const [0.0] == const [-0.0]); // expect: false
  print(identical(const [0.0], const [-0.0])); // expect: false
  print(identical(const C(0.0), const C(-0.0))); // expect: false
  print(identical(const [1], const [1.0])); // expect: false
  const t = z == 0.0 && 1 < 2 || false;
  print(t); // expect: true
  const st = '${z == 0.0}';
  print(st); // expect: true
  const cmp = [
    z < 0.0,
    z <= 0.0,
    z >= 0.0,
    z > 0,
    double.nan <= 1,
    1 < double.infinity,
    1 ~/ 2.0,
    -7 % 3,
    7 ~/ -2,
    5.5 % -2,
    1 / 0 == double.infinity,
    1 << 63,
    -1 >>> 1,
    2 - 3.0,
    -(-0.0),
    -0.0 + 0.0,
  ];
  print(cmp); // expect: [false, true, true, false, false, true, 0, 2, -3, 1.5, true, -9223372036854775808, 9223372036854775807, -1.0, 0.0, 0.0]
}
