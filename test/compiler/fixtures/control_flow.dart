import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64)>()
int choose(int a, int b) {
  if (a < b) return b - a;
  if (a == b) return 7;
  return a - b;
}

@Export<Int64 Function(Int64, Int64)>()
int conditional(int a, int b) => a <= b ? (a >= b ? 3 : a) : b;

bool positive(int value) => value > 0;
bool invert(bool value) => !value;

@Export<Int64 Function(Int64, Int64)>()
int shortCircuit(int a, int b) {
  var count = 0;
  final first = positive(a) && positive(++count + b);
  final second = invert(first) || positive(++count - b);
  return (first ? 10 : 20) + (second ? 1 : 2) + count;
}

@Export<Int64 Function(Int64)>()
int whileLoop(int limit) {
  var value = 0, total = 0;
  while (value < limit) {
    value++;
    if (value == 2) continue;
    if (value > 8) break;
    total += value;
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int doLoop(int limit) {
  var value = 0, total = 0;
  do {
    value++;
    if (value == 2) continue;
    total += value;
    if (value > 8) break;
  } while (value < limit);
  return total;
}

@Export<Int64 Function(Int64)>()
int forLoop(int limit) {
  var total = 0;
  for (var i = 0; i < limit; i++) {
    if (i > 8) break;
    if (i == 2) continue;
    total += increment(i);
  }
  return total;
}

int increment(int value) => value + 1;

@Export<Int64 Function(Int64)>()
int recursive(int value) {
  if (value <= 1) return value;
  return recursive(value - 1) + recursive(value - 2);
}

@Export<Int64 Function(Int64)>()
int rotate(int limit) {
  var a = 1, b = 2, c = 3;
  while (limit > 0) {
    final old = a;
    a = b;
    b = c;
    c = old;
    limit--;
  }
  return a + a + a + b + b + c;
}

@Export<Int64 Function(Int64)>()
int loopCalls(int limit) {
  var value = 1, total = 0;
  while (limit > 0) {
    final before = value + 7;
    value = increment(value);
    if (positive(limit - 2)) total += before;
    total += value + before;
    limit--;
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int foreverWithExit(int value) {
  while (true) {
    if (value <= 0) return value;
    value--;
  }
}

@Export<Int64 Function(Int64, Int64)>()
int relations(int a, int b) =>
    (a < b ? 1 : 0) +
    (a <= b ? 2 : 0) +
    (a > b ? 4 : 0) +
    (a >= b ? 8 : 0) +
    (a == b ? 16 : 0) +
    (a != b ? 32 : 0) +
    ((a < 0) == (b < 0) ? 64 : 0) +
    ((a < 0) != (b < 0) ? 128 : 0);

@Export<Int64 Function(Int64)>()
int nestedTransfers(int limit) {
  var total = 0;
  outer:
  for (var i = 0; i < limit && i < 5; i++) {
    for (var j = 0; j < 5; j++) {
      if (j == 1) continue;
      if (i == 2 && j == 3) continue outer;
      if (i == 3 && j == 2) break outer;
      total += i + j;
    }
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int deferredLocals(int count) {
  final int base;
  bool positiveCount;
  if (count > 0) {
    base = increment(count);
    positiveCount = true;
  } else {
    base = increment(-count);
    positiveCount = false;
  }
  int result;
  do {
    final int current;
    if (positiveCount) {
      current = count;
    } else {
      current = -count;
    }
    result = current + increment(base);
    count--;
  } while (count > 0);
  return result;
}

@Export<Double Function(Double, Int64)>()
double deferredDouble(double value, int count) {
  double result;
  do {
    result = value;
    value += 1.0;
    count--;
  } while (count > 0);
  return result;
}

@Export<Pointer<Int64> Function(Pointer<Int64>, Int64)>()
Pointer<Int64> deferredPointer(Pointer<Int64> value, int count) {
  final Pointer<Int64> result;
  if (count > 0) {
    result = value + increment(count);
  } else {
    result = value;
  }
  return result;
}
