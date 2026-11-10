import 'dart:ffi';

import 'package:dartc/interop.dart';

const _minimum = -0x8000000000000000;
const _maximum = 0x7fffffffffffffff;
const _negativeZero = -0.0;

int? _integer(int mode) {
  if (mode < 0) return null;
  if (mode == 0) return _minimum;
  return _maximum;
}

double? _floating(int mode) {
  if (mode < 0) return null;
  if (mode == 0) return _negativeZero;
  if (mode == 1) return 1.5;
  return double.nan;
}

bool? _boolean(int mode) => mode < 0 ? null : mode > 0;
int? _keep(int? value) => value;
int? _fallback(int evaluated) => 7;
bool _positive(int value, int evaluated) => value > 0;

@Export<Int64 Function(Int64)>()
int integer(int mode) {
  final value = _integer(mode);
  if (value == null) return 17;
  return value;
}

@Export<Double Function(Int64)>()
double floating(int mode) => _floating(mode) ?? 2.5;

@Export<Int64 Function(Int64)>()
int boolean(int mode) {
  final value = _boolean(mode);
  if (value == null) return 2;
  return value ? 1 : 0;
}

@Export<Int64 Function(Int64)>()
int predicates(int mode) {
  final value = _integer(mode);
  return (value is int ? 1 : 0) |
      (value is! int ? 2 : 0) |
      (value is num ? 4 : 0) |
      (value is Object ? 8 : 0) |
      (value == null ? 16 : 0) |
      (value != null ? 32 : 0);
}

@Export<Int64 Function(Int64)>()
int coalescing(int mode) {
  var calls = 0;
  var value = _integer(mode);
  value ??= _fallback(++calls);
  value ??= _fallback(++calls);
  final result = value ?? ++calls;
  return result + calls;
}

@Export<Int64 Function(Int64)>()
int shortCircuit(int mode) {
  var calls = 0;
  final value = _integer(mode);
  final first = value != null && _positive(value, ++calls);
  final second = value == null || _positive(value, ++calls);
  return (first ? 10 : 0) + (second ? 20 : 0) + calls;
}

@Export<Int64 Function(Int64)>()
int rotate(int count) {
  int? a = 1, b, c = 2;
  var total = 0;
  for (var i = 0; i < count; i++) {
    final old = a;
    a = b;
    b = c;
    c = _keep(old);
    total += a ?? 0;
  }
  return total;
}
