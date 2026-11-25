void main() {
  final l = [
    1.0,
    1.5,
    -0.0,
    0.0,
    double.nan,
    double.infinity,
    -double.infinity,
    1e300,
    3.25,
    1e21,
    1e20,
    123456789012345680000.0,
    1e-7,
    0.000001,
    5e-324,
    1.7976931348623157e308,
    0.1 + 0.2,
    100.0,
    1e100,
    1 / 3,
    2 / 3,
    123.456,
    1e22,
    0.00001234,
    9007199254740993.0,
    4.35,
    0.3,
    2.2250738585072014e-308,
    1e23,
    8.41e21,
    5e-7,
    123e-20,
  ];
  for (var i = 0; i < l.length; i++) {
    print(l[i]);
    print(-l[i]);
  }
  // expect: 1.0
  // expect: -1.0
  // expect: 1.5
  // expect: -1.5
  // expect: -0.0
  // expect: 0.0
  // expect: 0.0
  // expect: -0.0
  // expect: NaN
  // expect: NaN
  // expect: Infinity
  // expect: -Infinity
  // expect: -Infinity
  // expect: Infinity
  // expect: 1e+300
  // expect: -1e+300
  // expect: 3.25
  // expect: -3.25
  // expect: 1e+21
  // expect: -1e+21
  // expect: 100000000000000000000.0
  // expect: -100000000000000000000.0
  // expect: 123456789012345680000.0
  // expect: -123456789012345680000.0
  // expect: 1e-7
  // expect: -1e-7
  // expect: 0.000001
  // expect: -0.000001
  // expect: 5e-324
  // expect: -5e-324
  // expect: 1.7976931348623157e+308
  // expect: -1.7976931348623157e+308
  // expect: 0.30000000000000004
  // expect: -0.30000000000000004
  // expect: 100.0
  // expect: -100.0
  // expect: 1e+100
  // expect: -1e+100
  // expect: 0.3333333333333333
  // expect: -0.3333333333333333
  // expect: 0.6666666666666666
  // expect: -0.6666666666666666
  // expect: 123.456
  // expect: -123.456
  // expect: 1e+22
  // expect: -1e+22
  // expect: 0.00001234
  // expect: -0.00001234
  // expect: 9007199254740992.0
  // expect: -9007199254740992.0
  // expect: 4.35
  // expect: -4.35
  // expect: 0.3
  // expect: -0.3
  // expect: 2.2250738585072014e-308
  // expect: -2.2250738585072014e-308
  // expect: 1e+23
  // expect: -1e+23
  // expect: 8.41e+21
  // expect: -8.41e+21
  // expect: 5e-7
  // expect: -5e-7
  // expect: 1.23e-18
  // expect: -1.23e-18
}
