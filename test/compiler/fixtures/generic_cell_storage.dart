import 'dart:ffi';

import 'package:dartc/interop.dart';

T Function(T, bool) capture<T>(T initial) {
  var current = initial;
  return (next, write) {
    if (write) current = next;
    return current;
  };
}

num Function(num, bool)? retained;

@Export<Void Function(Int64)>()
void installCell(int initial) {
  retained = capture<num>(initial);
}

@Export<Void Function(Int64, Int64)>()
void writeCell(int next, int fractional) {
  retained!(fractional == 0 ? next : next + 0.5, true);
}

@Export<Double Function()>()
double readCell() => retained!(0, false).toDouble();

@Export<Int64 Function(Int64)>()
int localRoundTrip(int value) => capture<int>(value)(value, false);
