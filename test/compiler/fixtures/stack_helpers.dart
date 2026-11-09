import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef TenNative = Int64 Function(
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
);

@Export<TenNative>()
int weighted10(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  int j,
) {
  var value = doubleValue(a) + b;
  value = doubleValue(value) + c;
  value = doubleValue(value) + d;
  value = doubleValue(value) + e;
  value = doubleValue(value) + f;
  value = doubleValue(value) + g;
  value = doubleValue(value) + h;
  value = doubleValue(value) + i;
  return doubleValue(value) + j;
}

int doubleValue(int value) => value + value;

int span11(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  int j,
  int k,
) => a - k;
