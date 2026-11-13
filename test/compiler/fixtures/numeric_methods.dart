import 'dart:ffi';

import 'package:dartc/interop.dart';

import '../../frontend/lowering/fixtures/constant_safety/numeric.dart'
    as constants;

T identity<T>(T value) => value;

num method(num value, int mode) => switch (mode) {
  0 => value.abs(),
  1 => value.sign,
  2 => value.isNegative ? 1 : 0,
  3 => value.isNaN ? 1 : 0,
  4 => value.isInfinite ? 1 : 0,
  5 => value.isFinite ? 1 : 0,
  6 => -value,
  _ => value.toDouble(),
};

@Export<Double Function(Double, Int64)>()
double floating(double value, int mode) =>
    method(identity<num>(value), mode).toDouble();

@Export<Double Function(Int64, Int64)>()
double integer(int value, int mode) =>
    method(identity<num>(value), mode).toDouble();

@Export<Int64 Function(Double, Double, Int64, Int64)>()
int order(double left, double right, int integer, int mode) => switch (mode) {
  0 => left.compareTo(right),
  1 => left.compareTo(integer),
  2 => integer.compareTo(left),
  3 => identity<num>(left).compareTo(identity<num>(integer)),
  4 => left.compareTo.call(integer),
  _ => identity<num>(integer).compareTo.call(left),
};

@Export<Double Function(Double, Double, Double, Int64)>()
double clamp(double value, double lower, double upper, int mode) {
  try {
    return switch (mode) {
      0 => value.clamp(lower, upper).toDouble(),
      1 => identity<num>(value).clamp(lower, upper).toDouble(),
      _ => 0.clamp(lower, upper).toDouble(),
    };
  } on ArgumentError {
    return 12345.0;
  }
}

@Export<Double Function(Int64, Double, Int64, Int64)>()
double arithmetic(int integer, double floating, int shape, int operation) {
  final num left = shape < 2 ? identity<num>(integer) : identity<num>(floating);
  final num right = shape.isEven
      ? identity<num>(integer)
      : identity<num>(floating);
  final result = switch (operation) {
    0 => left + right,
    1 => left - right,
    2 => left * right,
    _ => left / right,
  };
  return result.toDouble();
}

@Export<Bool Function(Int64)>()
bool constantIdentity(int mode) => mode == 8
    ? const constants.IdentityBox().value
    : const [
        constants.mixedIdentity,
        constants.reversedIdentity,
        constants.roundedIdentity,
        constants.zeroIdentity,
        constants.integerIdentity,
        constants.doubleIdentity,
        constants.contextualIdentity,
        constants.distinctZeros,
      ][mode];
