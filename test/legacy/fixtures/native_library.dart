import 'dart:ffi';

import 'package:dartc/export.dart';

@Export<
  Int64 Function(Int8, Uint8, Int16, Uint16, Int32, Uint32, IntPtr, UintPtr)
>()
int words(int a0, int a1, int a2, int a3, int a4, int a5, int a6, int a7) =>
    a0 + a1 * 2 + a2 * 3 + a3 * 4 + a4 * 5 + a5 * 6 + a6 * 7 + a7 * 8;
@Export<Double Function(Double, Float, Int8, Uint16)>()
double mixed(double a0, double a1, int a2, int a3) =>
    a0 + a1 * 2 + a2 * 3 + a3 * 4;
@Export<Int8 Function(Int64)>()
int small_result(int a0) => a0 + 258;
@Export<Uint32 Function(Int64)>()
int u32_result(int a0) => a0 - 1;
@Export<Int32 Function(Int64)>()
int i32_result(int a0) => a0;
@Export<Bool Function(Bool, Int64)>()
bool boolean(bool a0, int a1) => a0 && a1 >= 0;
@Export<Pointer<Int8> Function(Pointer<Int8>)>()
Pointer<Int8> pointer(Pointer<Int8> a0) => a0;
@Export<Void Function()>()
void nothing() {}
@Export<Float Function(Float, Int8)>()
double recurse(double a0, int a1) {
  if (a1 <= 0) return a0;
  return recurse(a0 + 0.5, a1 - 1);
}

@Export<Double Function(Double)>()
double internal_call(double a0) => recurse(a0, 3);
@Export<
  Double Function(
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
    Int8,
    Uint8,
    Int16,
    Uint16,
    Int32,
    Uint32,
    Float,
    Double,
    Bool,
    Int64,
  )
>()
double packed(
  int a0,
  double a1,
  int a2,
  double a3,
  int a4,
  double a5,
  int a6,
  double a7,
  int a8,
  double a9,
  int a10,
  double a11,
  int a12,
  double a13,
  int a14,
  double a15,
  int a16,
  int a17,
  int a18,
  int a19,
  int a20,
  int a21,
  double a22,
  double a23,
  bool a24,
  int a25,
) =>
    0.0 +
    a0 * 1 +
    a1 * 2 +
    a2 * 3 +
    a3 * 4 +
    a4 * 5 +
    a5 * 6 +
    a6 * 7 +
    a7 * 8 +
    a8 * 9 +
    a9 * 10 +
    a10 * 11 +
    a11 * 12 +
    a12 * 13 +
    a13 * 14 +
    a14 * 15 +
    a15 * 16 +
    a16 * 17 +
    a17 * 18 +
    a18 * 19 +
    a19 * 20 +
    a20 * 21 +
    a21 * 22 +
    a22 * 23 +
    a23 * 24 +
    (a24 ? 1 : -1) * 25 +
    a25 * 26;
@Export<Int8>()
const int i8 = 257;
@Export<Uint8>()
const int u8 = -1;
@Export<Int16>()
const int i16 = 65535;
@Export<Uint16>()
const int u16 = -1;
@Export<Int32>()
const int i32 = 4294967297;
@Export<Uint32>()
const int u32 = -1;
@Export<Int64>()
const int i64 = -9223372036854775808;
@Export<Uint64>()
const int u64 = -1;
@Export<Bool>()
const bool b = true;
@Export<Double>()
const double double_value = 3.141592653589793;
@Export<Float>()
const double f0 = 0.0;
@Export<Float>()
const double f1 = -0.0;
@Export<Float>()
const double f2 = 3.141592653589793;
@Export<Float>()
const double f3 = 1.000000059604644775390625;
@Export<Float>()
const double f4 = 1.000000178813934326171875;
@Export<Float>()
const double f5 = 1.1754943508222875e-38;
@Export<Float>()
const double f6 = 1.1754942807573643e-38;
@Export<Float>()
const double f7 = 1.401298464324817e-45;
@Export<Float>()
const double f8 = 7.006492321624085e-46;
@Export<Float>()
const double f9 = 7.006492321624086e-46;
@Export<Float>()
const double f10 = 3.4028234663852886e38;
@Export<Float>()
const double f11 = 3.4028235677973366e38;
@Export<Float>()
const double f12 = 1e300;
@Export<Float>()
const double f13 = -1e300;
@Export<Float>()
const double f14 = 1e-300;
@Export<Float>()
const double f15 = -1e-300;
@Export<Float>()
const double positive_inf = 1.0 / 0.0;
@Export<Float>()
const double negative_inf = -1.0 / 0.0;
@Export<Int64 Function()>()
int original() => i8;

@Export<Int64 Function(Int64)>(symbol: 'class')
int keyword(int value) => value + 1;
@Export<Int64 Function(Int64)>(symbol: '加🙂')
int unicode(int value) => value + 2;
@Export<Int64 Function(Int64)>(symbol: 'math.add')
int punctuation(int value) => value + 3;
@Export<Int64>(symbol: 'int_least32_t')
const int typeName = 44;
@Export<Int64>(symbol: 'SIZE_MAX')
const int macroName = 45;
@Export<Int64>(symbol: 'dartc_export_0063006c006100730073')
const int aliasName = 46;
@Export<
  Pointer<NativeFunction<Int64 Function(Int64)>> Function(
    Pointer<NativeFunction<Int64 Function(Int64)>>,
  )
>()
Pointer<NativeFunction<Int64 Function(Int64)>> callback(
  Pointer<NativeFunction<Int64 Function(Int64)>> value,
) => value;
@Export<Pointer<Pointer<Int64>> Function(Pointer<Pointer<Int64>>)>()
Pointer<Pointer<Int64>> nested(Pointer<Pointer<Int64>> value) => value;
