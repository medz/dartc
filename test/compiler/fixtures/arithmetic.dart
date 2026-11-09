import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64)>(symbol: 'native_add')
int add(int left, int right) => left + right;

@Export<Int64 Function(Int64, Int64)>()
int reverse(int left, int right) => right - left;

@Export<Int64 Function(Int64)>()
int twice(int value) => value + value;

@Export<Int64 Function(Int64)>()
int increment(int value) => value + 1;

@Export<Int64 Function()>()
int literal() => 0x123456789abcdef0;

@Export<Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64)>()
int mixed(int a, int b, int c, int d, int e, int f) => a - b + c - d + e - f;
