import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Float Function(Float)>()
double identity(double value) => value;

@Export<Double Function(Float)>()
double widen(double value) => value;

@Export<Float Function(Double)>()
double narrow(double value) => value;

@Export<Double Function(Double)>()
double internal(double value) => identity(value) + widen(value) + narrow(value);

@Export<Pointer<Float> Function(Int64)>()
Pointer<Float> fromFloatAddress(int address) => .fromAddress(address);

@Export<Pointer<Double> Function(Int64)>()
Pointer<Double> fromDoubleAddress(int address) => .fromAddress(address);

@Export<Double Function(Pointer<Float>)>()
double readFloat(Pointer<Float> pointer) => pointer.value;

@Export<Double Function(Pointer<Double>)>()
double readDouble(Pointer<Double> pointer) => pointer.value;

@Export<Double Function(Pointer<Float>, Double)>()
double writeFloat(Pointer<Float> pointer, double value) {
  pointer.value = value;
  return value;
}

@Export<Double Function(Pointer<Double>, Double)>()
double writeDouble(Pointer<Double> pointer, double value) {
  pointer.value = value;
  return value;
}

@Export<Double Function(Pointer<Float>, Double)>()
double update(Pointer<Float> pointer, double value) => pointer.value += value;

@Export<Double Function(Pointer<Float>)>()
double postIncrement(Pointer<Float> pointer) => pointer.value++;

@Export<Double Function(Pointer<Float>, Pointer<Float>, Double)>()
double alias(Pointer<Float> left, Pointer<Float> right, double value) {
  left.value = value;
  right.value = left.value + value;
  return left.value;
}

typedef MixedNative = Double Function(
  Float,
  Double,
  Float,
  Double,
  Float,
  Double,
  Float,
  Double,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Float,
  Float,
  Int8,
  Double,
  Pointer<Double>,
);
typedef MixedDart = double Function(
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  double,
  double,
  int,
  double,
  Pointer<Double>,
);

@Export<MixedNative>()
double mixed(
  double f0,
  double f1,
  double f2,
  double f3,
  double f4,
  double f5,
  double f6,
  double f7,
  int i0,
  int i1,
  int i2,
  int i3,
  int i4,
  int i5,
  int i6,
  int i7,
  double f8,
  double f9,
  int i8,
  double f10,
  Pointer<Double> pointer,
) =>
    f0 +
    f1 +
    f2 +
    f3 +
    f4 +
    f5 +
    f6 +
    f7 +
    i0 +
    i1 +
    i2 +
    i3 +
    i4 +
    i5 +
    i6 +
    i7 +
    f8 +
    f9 +
    i8 +
    f10 +
    pointer.value;
