import 'dart:ffi';

import 'package:dartc/export.dart';

import 'call_helpers.dart' as helper;

@Export<Int64 Function(Int64, Int64)>()
int calls(int a, int b) {
  final before = a + b;
  final first = helper.subtract(b, a);
  final second = helper.twice(first);
  return before + first - second + a + helper.offset(7) + _difference(a, b);
}

int _difference(int a, int b) => b - a;

@Export<Int64 Function(Int64)>()
int repeated(int value) => helper.add(value, value);

@Export<Int64 Function(Int64)>()
int sameOperands(int value) {
  final zero = value - value;
  return zero + value;
}

@Export<Int64 Function()>()
int literalCall() => helper.subtract(42, 1);

@Export<Int64 Function(Int64)>()
int unusedCall(int value) {
  helper.subtract(value, 1);
  return value;
}

@Export<Int64 Function(Int64)>()
int pressure(int a) {
  final b = a + 1, c = a + 2, d = a + 3, e = a + 4;
  final f = a + 5, g = a + 6, h = a + 7, i = a + 8;
  final j = a + 9, k = a + 10, l = a + 11, m = a + 12;
  final n = a + 13, o = a + 14, p = a + 15, q = a + 16;
  return b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + q;
}
