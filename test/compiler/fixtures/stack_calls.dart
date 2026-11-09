import 'package:dartc/interop.dart';

import 'stack_helpers.dart';

@Export<TenNative>()
int last10(
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
) => j;

@Export<TenNative>()
int forward10(
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
  final before = a - j;
  final largest = span11(a, b, c, d, e, f, g, h, i, j, j);
  final first = weighted10(j, i, h, g, f, e, d, c, b, a);
  final second = weighted10(first, a, a, -3, 5, i, j, first, b, j);
  return before + largest + first - second + i + j + doubleValue(a);
}

@Export<TenNative>()
int rotate10(
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
  for (var step = 0; step < 3; step++) {
    final first = a;
    a = b;
    b = c;
    c = d;
    d = e;
    e = f;
    f = g;
    g = h;
    h = i;
    i = j;
    j = first;
  }
  return weighted10(a, b, c, d, e, f, g, h, i, j);
}
