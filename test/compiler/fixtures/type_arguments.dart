import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show Box, churn;

typedef Pair = (int, {bool flag});
typedef FunctionA = T Function<T extends num>(T);
typedef FunctionB = U Function<U extends num>(U);
typedef VoidType = void;
typedef Top = Object?;
typedef FutureObject = FutureOr<Object>;

Type typeOf<T>() => T;

int inspect<T>(Type expected, int depth, int count) {
  if (depth > 0) return inspect<T>(expected, depth - 1, count);
  churn(count);
  return T == expected ? 1 : 0;
}

int forward<A, B>(int depth, int count) =>
    inspect<B>(typeOf<A>(), depth, count);

@Export<Int64 Function(Int64, Int64, Int64)>()
int types(int mode, int depth, int count) => switch (mode) {
  0 => forward<int, int>(depth, count),
  1 => forward<int, num>(depth, count),
  2 => forward<double, double>(depth, count),
  3 => forward<int?, int>(depth, count),
  4 => forward<Never?, Null>(depth, count),
  5 => forward<Never, Null>(depth, count),
  6 => forward<Box<int>, Box<num>>(depth, count),
  7 => forward<Pair, (int, {bool flag})>(depth, count),
  8 => forward<FunctionA, FunctionB>(depth, count),
  9 => forward<dynamic, Top>(depth, count),
  10 => forward<VoidType, dynamic>(depth, count),
  11 => forward<FutureObject, Object>(depth, count),
  12 => forward<FutureOr<int>, FutureOr<num>>(depth, count),
  _ => forward<FutureOr<int?>, FutureOr<int?>>(depth, count),
};

int many<A, B, C, D, E, F, G, H, I, J>(
  int a,
  int b,
  double c,
  int depth,
  int count,
) {
  if (depth > 0) {
    return many<A, B, C, D, E, F, G, H, I, J>(a, b, c, depth - 1, count);
  }
  churn(count);
  return a +
      b +
      (c > 0 ? 1 : 0) +
      (A == int ? 2 : 0) +
      (B == double ? 4 : 0) +
      (C == bool ? 8 : 0) +
      (D == Null ? 16 : 0) +
      (E == Never ? 32 : 0) +
      (F == (Box<int>) ? 64 : 0) +
      (G == (Box<num>) ? 128 : 0) +
      (H == Pair ? 256 : 0) +
      (I == FunctionA ? 512 : 0) +
      (J == Top ? 1024 : 0);
}

@Export<Int64 Function(Int64, Int64, Double, Int64, Int64)>()
int stack(int a, int b, double c, int depth, int count) =>
    many<
      int,
      double,
      bool,
      Null,
      Never,
      Box<int>,
      Box<num>,
      Pair,
      FunctionB,
      Top
    >(a, b, c, depth, count);

T identity<T>(T value, int count) {
  churn(count);
  return value;
}

@Export<Int64 Function(Int64, Int64)>()
int integer(int value, int count) => identity<int>(value, count);

@Export<Double Function(Double, Int64)>()
double floating(double value, int count) => identity<double>(value, count);
