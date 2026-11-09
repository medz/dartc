import 'dart:ffi';

import 'package:dartc/export.dart';

typedef BinaryNative = Double Function(Double, Double);
typedef BinaryDart = double Function(double, double);
typedef UnaryNative = Double Function(Double);
typedef UnaryDart = double Function(double);

@Export<BinaryNative>()
double add(double left, double right) => left + right;

@Export<BinaryNative>()
double subtract(double left, double right) => left - right;

@Export<BinaryNative>()
double multiply(double left, double right) => left * right;

@Export<BinaryNative>()
double divide(double left, double right) => left / right;

@Export<UnaryNative>()
double negate(double value) => -value;

@Export<Int64 Function(Double, Double)>()
int comparisons(double left, double right) =>
    (left == right ? 1 : 0) +
    (left != right ? 2 : 0) +
    (left < right ? 4 : 0) +
    (left <= right ? 8 : 0) +
    (left > right ? 16 : 0) +
    (left >= right ? 32 : 0);

@Export<Double Function()>()
double negativeZero() => -0.0;

@Export<Double Function()>()
double tiny() => 1e-310;

@Export<Double Function()>()
double infinity() => double.infinity;

@Export<Double Function()>()
double nan() => double.nan;

double step(double value) => value * 1.25 + 0.5;

@Export<Double Function(Double, Double, Int64)>()
double rotate(double left, double right, int count) {
  for (var i = 0; i < count; i++) {
    final previous = left;
    left = right;
    right = step(previous);
  }
  return count < 0 ? -left : left + right;
}

@Export<UnaryNative>()
double pressure(double x) {
  final v0 = x + 1.25;
  final v1 = x + 2.25;
  final v2 = x + 3.25;
  final v3 = x + 4.25;
  final v4 = x + 5.25;
  final v5 = x + 6.25;
  final v6 = x + 7.25;
  final v7 = x + 8.25;
  final v8 = x + 9.25;
  final v9 = x + 10.25;
  final v10 = x + 11.25;
  final v11 = x + 12.25;
  final v12 = x + 13.25;
  final v13 = x + 14.25;
  final v14 = x + 15.25;
  final v15 = x + 16.25;
  final v16 = x + 17.25;
  final v17 = x + 18.25;
  final v18 = x + 19.25;
  final v19 = x + 20.25;
  final v20 = x + 21.25;
  final v21 = x + 22.25;
  final v22 = x + 23.25;
  final v23 = x + 24.25;
  final v24 = x + 25.25;
  final v25 = x + 26.25;
  final v26 = x + 27.25;
  final v27 = x + 28.25;
  final result = step(x);
  return v0 +
      v1 +
      v2 +
      v3 +
      v4 +
      v5 +
      v6 +
      v7 +
      v8 +
      v9 +
      v10 +
      v11 +
      v12 +
      v13 +
      v14 +
      v15 +
      v16 +
      v17 +
      v18 +
      v19 +
      v20 +
      v21 +
      v22 +
      v23 +
      v24 +
      v25 +
      v26 +
      v27 +
      result;
}

typedef MixedNative = Double Function(
  Pointer<Int64>,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
  Double,
  Int64,
);

typedef MixedDart = double Function(
  Pointer<Int64>,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
  double,
  int,
);

@Export<MixedNative>()
double mixed(
  Pointer<Int64> trace,
  double d0,
  int i0,
  double d1,
  int i1,
  double d2,
  int i2,
  double d3,
  int i3,
  double d4,
  int i4,
  double d5,
  int i5,
  double d6,
  int i6,
  double d7,
  int i7,
  double d8,
  int i8,
) {
  final changed = step(d0 + 0.125);
  trace.value =
      i0 * 1 +
      i1 * 2 +
      i2 * 3 +
      i3 * 4 +
      i4 * 5 +
      i5 * 6 +
      i6 * 7 +
      i7 * 8 +
      i8 * 9;
  return d0 * 1.0 +
      d1 * 2.0 +
      d2 * 3.0 +
      d3 * 4.0 +
      d4 * 5.0 +
      d5 * 6.0 +
      d6 * 7.0 +
      d7 * 8.0 +
      d8 * 9.0 +
      changed;
}

@Export<MixedNative>()
double forward(
  Pointer<Int64> trace,
  double d0,
  int i0,
  double d1,
  int i1,
  double d2,
  int i2,
  double d3,
  int i3,
  double d4,
  int i4,
  double d5,
  int i5,
  double d6,
  int i6,
  double d7,
  int i7,
  double d8,
  int i8,
) => mixed(
  trace,
  d8,
  i8,
  d7,
  i7,
  d6,
  i6,
  d5,
  i5,
  d4,
  i4,
  d3,
  i3,
  d2,
  i2,
  d1,
  i1,
  d0,
  i0,
);

@Export<Double Function(Pointer<Int64>)>()
double constantsInCall(Pointer<Int64> trace) => mixed(
  trace,
  1.25,
  1,
  2.25,
  2,
  3.25,
  3,
  4.25,
  4,
  5.25,
  5,
  6.25,
  6,
  7.25,
  7,
  8.25,
  8,
  9.25,
  9,
);
