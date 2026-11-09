import 'dart:ffi';

import 'package:dartc/export.dart';

import 'pointer_helpers.dart' show customMember;

@Export<Pointer<Int64> Function(Int64)>()
Pointer<Int64> fromAddress(int address) => .fromAddress(address);

@Export<Int64 Function(Pointer<Int64>)>()
int address(Pointer<Int64> pointer) => pointer.address;

@Export<Int64 Function(Pointer<Int64>)>()
int read(Pointer<Int64> pointer) => pointer.value;

@Export<Void Function(Pointer<Int64>, Int64)>()
void write(Pointer<Int64> pointer, int value) {
  pointer.value = value;
}

@Export<Int64 Function(Pointer<Int64>, Pointer<Int64>)>()
int equal(Pointer<Int64> left, Pointer<Int64> right) => left == right ? 1 : 0;

@Export<Pointer<Int64> Function(Pointer<Int64>, Pointer<Int64>, Int64)>()
Pointer<Int64> rotate(Pointer<Int64> left, Pointer<Int64> right, int count) {
  for (var i = 0; i < count; i++) {
    final previous = left;
    left = right;
    right = previous;
    write(left, read(left) + i);
  }
  return count < 0 ? right : left;
}

@Export<Int64 Function(Pointer<Int64>, Pointer<Int64>)>()
int update(Pointer<Int64> trace, Pointer<Int64> pointer) {
  final old = receiver(trace, pointer).value++;
  receiver(trace, pointer).value += operand(trace);
  return old;
}

Pointer<Int64> receiver(Pointer<Int64> trace, Pointer<Int64> pointer) {
  trace.value = trace.value * 10 + 1;
  return pointer;
}

int operand(Pointer<Int64> trace) {
  trace.value = trace.value * 10 + 2;
  return 7;
}

typedef MixedNative = Pointer<Int64> Function(
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
  Pointer<Int64>,
  Int64,
);
typedef MixedDart = Pointer<Int64> Function(
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
  Pointer<Int64>,
  int,
);

@Export<MixedNative>()
Pointer<Int64> mixed(
  Pointer<Int64> a,
  int b,
  Pointer<Int64> c,
  int d,
  Pointer<Int64> e,
  int f,
  Pointer<Int64> g,
  int h,
  Pointer<Int64> i,
  int j,
) {
  write(i, a.value + b + c.value + d + e.value + f + g.value + h + i.value + j);
  return g;
}

@Export<MixedNative>()
Pointer<Int64> forward(
  Pointer<Int64> a,
  int b,
  Pointer<Int64> c,
  int d,
  Pointer<Int64> e,
  int f,
  Pointer<Int64> g,
  int h,
  Pointer<Int64> i,
  int j,
) => mixed(i, j, g, h, e, f, c, d, a, b);

@Export<Int64 Function(Pointer<Int64>)>()
int declaredMember(Pointer<Int64> pointer) => customMember(pointer);
