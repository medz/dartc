import 'dart:ffi';

import 'package:dartc/interop.dart';

int? _integer(int value) => value;
double? _floating(double value) => value;
int? _maybe(int value, int select) => select == 0 ? null : value;

@Export<Int64 Function(Int64, Int64)>()
int heldInteger(int value, int count) {
  final held = _integer(value + 1);
  for (var i = 0; i < count; i++) {
    _integer(i);
  }
  if (held == null) return -1;
  return held;
}

@Export<Double Function(Double, Int64)>()
double heldFloating(double value, int count) {
  final held = _floating(-value);
  for (var i = 0; i < count; i++) {
    _floating(value + i);
  }
  if (held == null) return -1;
  return held;
}

@Export<Int64 Function(Int64, Int64)>()
int optional(int value, int select) {
  final selected = _maybe(value, select);
  if (selected == null) return -1;
  return selected;
}
