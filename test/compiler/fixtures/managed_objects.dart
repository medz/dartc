import 'dart:ffi';

import 'package:dartc/interop.dart';

class Allocation(
  int input,
  final double fraction,
  final Allocation? previous,
  Pointer<Int64> output,
) {
  final int value = input;

  this {
    if (output.address != 0) {
      output.value += input;
    }
  }
}

@Export<Float Function(Int32, Double, Pointer<Int64>)>()
double allocateAndNotify(int count, double fraction, Pointer<Int64> output) {
  Allocation? previous;
  for (var i = 0; i < count; i++) {
    previous = Allocation(i, fraction, previous, output);
  }
  return fraction;
}

void main() => allocateAndNotify(40000, 1.25, .fromAddress(0));

class StackPointerArguments(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  Pointer<Int64> output,
) {
  this {
    output.value = a + b + c + d + e + f + g + h;
  }
}

@Export<Void Function(Pointer<Int64>)>()
void constructStackPointer(Pointer<Int64> output) =>
    StackPointerArguments(1, 2, 3, 4, 5, 6, 7, 8, output);

class NumericConstruction<I extends int, F extends double>(
  I integer,
  F floating,
  int count,
  Pointer<Int64> integers,
  Pointer<Double> doubles,
) {
  this {
    allocateAndNotify(count, 0.0, .fromAddress(0));
    integers.value = integer;
    doubles.value = floating;
  }
}

@Export<Void Function(Int64, Double, Int64, Pointer<Int64>, Pointer<Double>)>()
void constructNumbers(
  int integer,
  double floating,
  int count,
  Pointer<Int64> integers,
  Pointer<Double> doubles,
) => NumericConstruction(integer, floating, count, integers, doubles);
