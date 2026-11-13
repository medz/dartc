import 'dart:ffi';
import 'dart:math' as math;

import 'package:dartc/interop.dart';

import 'math_export.dart' as alias;

@Export<Double Function(Double)>()
double squareRoot(double value) => math.sqrt(value);

@Export<Double Function(Int64)>()
double integerRoot(int value) => alias.sqrt(value);

@Export<Double Function(Double)>()
double liveInput(double value) => math.sqrt(value) + value;

@Export<Double Function(Double)>()
double nested(double value) {
  final root = math.sqrt(value);
  return squareRoot(root) + root + value;
}

@Export<Double Function(Int64, Double)>()
double iterate(int count, double value) {
  for (var i = 0; i < count; i++) {
    value = math.sqrt(value) + 1;
  }
  return value;
}

@Export<Double Function(Pointer<Double>)>()
double ordered(Pointer<Double> memory) => math.sqrt(memory.value++);

double numberRoot(num value) => math.sqrt(value);
double dynamicRoot(dynamic value) => math.sqrt(value);

double sqrt(double value) => value + 100;

class LocalMath() {
  static double sqrt(double value) => value + 10;
}

@Export<Double Function(Double)>()
double shadowed(double value) => sqrt(value) + LocalMath.sqrt(value);

final _root = alias.sqrt;

@Export<Double Function(Double, Int64, Int32)>()
double boxedRoot(double floating, int integer, int mode) {
  final num value = mode.isEven ? floating : integer;
  switch (mode ~/ 2) {
    case 0:
      return numberRoot(value);
    case 1:
      return dynamicRoot(value);
    case 2:
      return _root(value);
    default:
      final dynamic root = _root;
      return root(value);
  }
}

@Export<Int32 Function(Int32)>()
int rejectedRoot(int mode) {
  final dynamic value = switch (mode ~/ 2) {
    0 => null,
    1 => true,
    _ => '9',
  };
  try {
    if (mode.isEven) {
      math.sqrt(value);
    } else {
      final dynamic root = _root;
      root(value);
    }
  } on TypeError {
    return 1;
  }
  return 0;
}

@Export<Double Function(Int32, Double, Double)>()
double floatingMath(int operation, double x, double y) => switch (operation) {
  0 => math.sin(x),
  1 => math.cos(x),
  2 => math.tan(x),
  3 => math.asin(x),
  4 => math.acos(x),
  5 => math.atan(x),
  6 => math.exp(x),
  7 => math.log(x),
  8 => math.atan2(x, y),
  _ => math.pow(x, y) as double,
};

@Export<Int64 Function(Int64, Int64)>()
int integerPower(int base, int exponent) => math.pow(base, exponent) as int;

final _sine = alias.sin;
final _power = alias.pow;

@Export<Double Function(Double, Int64, Int32)>()
double indirectMath(double floating, int integer, int mode) {
  final num value = mode.isEven ? floating : integer;
  if (mode < 2) return _sine(value);
  if (mode < 4) {
    final dynamic sine = _sine;
    return sine(value);
  }
  final exponent = mode < 8 ? 3 : -3;
  final dynamic power = _power;
  final num result = mode < 6
      ? _power(value, exponent)
      : power(value, exponent);
  if ((result is int) != (value is int && exponent >= 0)) {
    throw StateError('power result type');
  }
  return result.toDouble();
}

@Export<Double Function(Double, Double)>()
double composed(double x, double y) =>
    math.sin(x) + math.cos(x) + math.pow(x, y) + math.atan2(x, y);

@Export<Double Function(Pointer<Double>)>()
double orderedPower(Pointer<Double> memory) =>
    math.pow(memory.value++, memory.value++) as double;

@Export<Int32 Function(Int32)>()
int rejectedMath(int mode) {
  final dynamic value = switch (mode % 3) {
    0 => null,
    1 => true,
    _ => '9',
  };
  try {
    switch (mode ~/ 3) {
      case 0:
        math.sin(value);
      case 1:
        final dynamic power = _power;
        power(value, 2);
      default:
        _power(2, value);
    }
  } on TypeError {
    return 1;
  }
  return 0;
}
