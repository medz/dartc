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
