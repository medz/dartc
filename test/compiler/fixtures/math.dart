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
