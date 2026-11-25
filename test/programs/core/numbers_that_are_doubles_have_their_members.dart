void main() {
  for (final x in [
    0.0,
    -0.0,
    1.5,
    -1.5,
    2.5,
    -2.5,
    0.49999999999999994,
    1e17,
    -3.7,
    1e300,
    double.infinity,
    double.nan,
  ]) {
    print(
      '$x ${x.hashCode == (x * 1).hashCode} ${x.abs()} ${x.sign} ${x.isNegative} ${x.isNaN} ${x.isFinite} ${x.isInfinite} ${x.roundToDouble()} ${x.floorToDouble()} ${x.ceilToDouble()} ${x.truncateToDouble()} ${x.compareTo(1)} ${x.remainder(1.2)} ${x % 1.2} ${-x} ${x == 1.5} ${x < 2} ${x.toDouble()} ${x.toStringAsFixed(2)} ${x.toStringAsExponential(3)} ${x.toStringAsPrecision(4)} ${x.toStringAsExponential()} ${x.clamp(-2, 2)}',
    );
    if (x.isFinite)
      print('${x.toInt()} ${x.round()} ${x.floor()} ${x.ceil()} ${x ~/ 1}');
  }
  // expect: 0.0 true 0.0 0.0 false false true false 0.0 0.0 0.0 0.0 -1 0.0 0.0 -0.0 false true 0.0 0.00 0.000e+0 0.000 0e+0 0.0
  // expect: 0 0 0 0 0
  // expect: -0.0 true 0.0 -0.0 true false true false -0.0 -0.0 -0.0 -0.0 -1 -0.0 0.0 0.0 false true -0.0 -0.00 -0.000e+0 -0.000 -0e+0 -0.0
  // expect: 0 0 0 0 0
  // expect: 1.5 true 1.5 1.0 false false true false 2.0 1.0 2.0 1.0 1 0.30000000000000004 0.30000000000000004 -1.5 true true 1.5 1.50 1.500e+0 1.500 1.5e+0 1.5
  // expect: 1 2 1 2 1
  // expect: -1.5 true 1.5 -1.0 true false true false -2.0 -2.0 -1.0 -1.0 -1 -0.30000000000000004 0.8999999999999999 1.5 false true -1.5 -1.50 -1.500e+0 -1.500 -1.5e+0 -1.5
  // expect: -1 -2 -2 -1 -1
  // expect: 2.5 true 2.5 1.0 false false true false 3.0 2.0 3.0 2.0 1 0.10000000000000009 0.10000000000000009 -2.5 false false 2.5 2.50 2.500e+0 2.500 2.5e+0 2
  // expect: 2 3 2 3 2
  // expect: -2.5 true 2.5 -1.0 true false true false -3.0 -3.0 -2.0 -2.0 -1 -0.10000000000000009 1.0999999999999999 2.5 false true -2.5 -2.50 -2.500e+0 -2.500 -2.5e+0 -2
  // expect: -2 -3 -3 -2 -2
  // expect: 0.49999999999999994 true 0.49999999999999994 1.0 false false true false 0.0 0.0 1.0 0.0 -1 0.49999999999999994 0.49999999999999994 -0.49999999999999994 false true 0.49999999999999994 0.50 5.000e-1 0.5000 4.9999999999999994e-1 0.49999999999999994
  // expect: 0 0 0 1 0
  // expect: 100000000000000000.0 true 100000000000000000.0 1.0 false false true false 100000000000000000.0 100000000000000000.0 100000000000000000.0 100000000000000000.0 1 0.5007434154171886 0.5007434154171886 -100000000000000000.0 false false 100000000000000000.0 100000000000000000.00 1.000e+17 1.000e+17 1e+17 2
  // expect: 100000000000000000 100000000000000000 100000000000000000 100000000000000000 100000000000000000
  // expect: -3.7 true 3.7 -1.0 true false true false -4.0 -4.0 -3.0 -3.0 -1 -0.10000000000000031 1.0999999999999996 3.7 false true -3.7 -3.70 -3.700e+0 -3.700 -3.7e+0 -2
  // expect: -3 -4 -4 -3 -3
  // expect: 1e+300 true 1e+300 1.0 false false true false 1e+300 1e+300 1e+300 1e+300 1 0.45321850028067767 0.45321850028067767 -1e+300 false false 1e+300 1e+300 1.000e+300 1.000e+300 1e+300 2
  // expect: 9223372036854775807 9223372036854775807 9223372036854775807 9223372036854775807 9223372036854775807
  // expect: Infinity true Infinity 1.0 false false false true Infinity Infinity Infinity Infinity 1 NaN NaN -Infinity false false Infinity Infinity Infinity Infinity Infinity 2
  // expect: NaN true NaN NaN false true false false NaN NaN NaN NaN 1 NaN NaN NaN false false NaN NaN NaN NaN NaN 2
  for (final x in [1.5, 1.0, 0.1, 1e300, -2.25, 1e18, 1e19, 5e-324]) {
    print(x.hashCode);
  }
  // expect: 4609434219686920192
  // expect: 11601
  // expect: 4591870180277092355
  // expect: 4483302904550625696
  // expect: 562953174777856
  // expect: 781410608
  // expect: 279602388744037860
  // expect: 1
  for (final d in [0, 1, 2, 5, 20]) {
    print(2.5.toStringAsFixed(d));
    print(0.125.toStringAsFixed(d));
    print((-0.001).toStringAsFixed(d));
    print(1e20.toStringAsFixed(d));
    print(99.995.toStringAsFixed(d));
    print(0.5.toStringAsFixed(d));
  }
  // expect: 3
  // expect: 0
  // expect: -0
  // expect: 100000000000000000000
  // expect: 100
  // expect: 1
  // expect: 2.5
  // expect: 0.1
  // expect: -0.0
  // expect: 100000000000000000000.0
  // expect: 100.0
  // expect: 0.5
  // expect: 2.50
  // expect: 0.13
  // expect: -0.00
  // expect: 100000000000000000000.00
  // expect: 100.00
  // expect: 0.50
  // expect: 2.50000
  // expect: 0.12500
  // expect: -0.00100
  // expect: 100000000000000000000.00000
  // expect: 99.99500
  // expect: 0.50000
  // expect: 2.50000000000000000000
  // expect: 0.12500000000000000000
  // expect: -0.00100000000000000002
  // expect: 100000000000000000000.00000000000000000000
  // expect: 99.99500000000000454747
  // expect: 0.50000000000000000000
  for (final p in [1, 2, 3, 7, 21]) {
    print(123.456.toStringAsPrecision(p));
    print(0.00001234.toStringAsPrecision(p));
    print(99.99.toStringAsPrecision(p));
    print(0.0.toStringAsPrecision(p));
    print(1.25.toStringAsExponential(p - 1));
    print(0.0.toStringAsExponential(p - 1));
  }
  // expect: 1e+2
  // expect: 0.00001
  // expect: 1e+2
  // expect: 0
  // expect: 1e+0
  // expect: 0e+0
  // expect: 1.2e+2
  // expect: 0.000012
  // expect: 1.0e+2
  // expect: 0.0
  // expect: 1.3e+0
  // expect: 0.0e+0
  // expect: 123
  // expect: 0.0000123
  // expect: 100
  // expect: 0.00
  // expect: 1.25e+0
  // expect: 0.00e+0
  // expect: 123.4560
  // expect: 0.00001234000
  // expect: 99.99000
  // expect: 0.000000
  // expect: 1.250000e+0
  // expect: 0.000000e+0
  // expect: 123.456000000000003070
  // expect: 0.0000123400000000000004369
  // expect: 99.9899999999999948841
  // expect: 0.00000000000000000000
  // expect: 1.25000000000000000000e+0
  // expect: 0.00000000000000000000e+0
  for (final s in [
    '1',
    '1.5',
    '-2.25e3',
    '.5',
    '1.',
    ' 7 ',
    'Infinity',
    '-Infinity',
    'NaN',
    '1e400',
    '123456789012345678901234567890',
    '0.1e-5',
    '1e',
    'x',
    '',
    '+3',
    '0x10',
    '1_0',
    '4.9e-324',
    '2.4703282292062328e-324',
  ]) {
    print(double.tryParse(s));
  }
  // expect: 1.0
  // expect: 1.5
  // expect: -2250.0
  // expect: 0.5
  // expect: 1.0
  // expect: 7.0
  // expect: Infinity
  // expect: -Infinity
  // expect: NaN
  // expect: Infinity
  // expect: 1.2345678901234568e+29
  // expect: 0.000001
  // expect: null
  // expect: null
  // expect: null
  // expect: 3.0
  // expect: null
  // expect: null
  // expect: 5e-324
  // expect: 5e-324
  print(num.parse('3')); // expect: 3
  print(num.parse('3.0')); // expect: 3.0
  print(1.0.hashCode == 1.hashCode); // expect: true
  print(0.1 + 0.2 == 0.3); // expect: false
}
