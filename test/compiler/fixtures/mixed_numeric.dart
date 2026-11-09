import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<Double Function(Int64, Double)>()
double add(int a, double b) => a + b;
@Export<Double Function(Int64, Double)>()
double subtract(int a, double b) => a - b;
@Export<Double Function(Int64, Double)>()
double multiply(int a, double b) => a * b;
@Export<Double Function(Int64, Double)>()
double divide(int a, double b) => a / b;
@Export<Double Function(Double, Int64)>()
double reverseAdd(double a, int b) => a + b;
@Export<Double Function(Double, Int64)>()
double reverseSubtract(double a, int b) => a - b;
@Export<Double Function(Double, Int64)>()
double reverseMultiply(double a, int b) => a * b;
@Export<Double Function(Double, Int64)>()
double reverseDivide(double a, int b) => a / b;
@Export<Double Function(Int64, Int64)>()
double divideInts(int a, int b) => a / b;
@Export<Double Function(Int64)>()
double converted(int value) => value.toDouble();
@Export<Double Function(Double)>()
double doubleIdentity(double value) => value.toDouble();

@Export<Int64 Function(Int64, Double)>()
int comparisons(int i, double d) =>
    (i == d ? 1 : 0) |
    (i != d ? 2 : 0) |
    (i < d ? 4 : 0) |
    (i <= d ? 8 : 0) |
    (i > d ? 16 : 0) |
    (i >= d ? 32 : 0);

@Export<Int64 Function(Double, Int64)>()
int reverseComparisons(double d, int i) =>
    (d == i ? 1 : 0) |
    (d != i ? 2 : 0) |
    (d < i ? 4 : 0) |
    (d <= i ? 8 : 0) |
    (d > i ? 16 : 0) |
    (d >= i ? 32 : 0);

@Export<Int64 Function()>()
int constantComparison() => 9007199254740993 == 9007199254740992.0 ? 1 : 0;

const _integer = 9007199254740993;
const _floating = 9007199254740992.0;
const _equal = _integer == _floating;

@Export<Int64 Function()>(symbol: _equal ? 'incorrect' : 'constantValues')
int constantValues() {
  const local = _integer > _floating;
  return (_equal ? 1 : 0) |
      (local ? 2 : 0) |
      _constantDefault() |
      (_constantDefault(false) == 0 ? 8 : 0);
}

int _constantDefault([bool value = _integer != _floating]) => value ? 4 : 0;

@Export<Int64 Function()>()
int namedConstants() =>
    _constantNamed() * 100 +
    _constantNamed(first: 7) * 10 +
    _constantNamed(condition: false, first: 9);

int _constantNamed({
  int first = _integer > _floating ? 3 : 4,
  bool condition = _integer != _floating,
}) => condition ? first : 0;

@Export<Double Function(Int64, Double)>()
double pressure(int integer, double d) {
  final a0 = d + 1.0, a1 = d + 2.0, a2 = d + 3.0, a3 = d + 4.0;
  final a4 = d + 5.0, a5 = d + 6.0, a6 = d + 7.0, a7 = d + 8.0;
  final a8 = d + 9.0, a9 = d + 10.0, a10 = d + 11.0, a11 = d + 12.0;
  final a12 = d + 13.0, a13 = d + 14.0, a14 = d + 15.0;
  final quotient = integer / (integer + 1);
  return quotient +
      a0 +
      a1 +
      a2 +
      a3 +
      a4 +
      a5 +
      a6 +
      a7 +
      a8 +
      a9 +
      a10 +
      a11 +
      a12 +
      a13 +
      a14;
}

@Export<Double Function(Int64, Double)>()
double loop(int count, double d) {
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    sum += add(i, d);
  }
  return sum;
}

@Export<Int64 Function(Pointer<Int64>, Double)>()
int orderedComparison(Pointer<Int64> memory, double delta) {
  final left = memory.value++;
  final right = memory.value++ + delta;
  return left < right ? 1 : 0;
}
