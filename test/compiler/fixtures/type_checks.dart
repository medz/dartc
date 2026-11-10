import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

class Base();
class Child() extends Base;
abstract class Flag();
class Marked() extends Child implements Flag;
class Box<T>();
class Projected<T>() extends Box<T> implements Flag;

Object? value(int mode, int seed) => switch (mode) {
  0 => seed,
  1 => seed + 0.5,
  2 => seed > 0,
  3 => null,
  4 => Base(),
  5 => Child(),
  6 => Marked(),
  7 => Box<int>(),
  8 => Box<num>(),
  9 => Box<int?>(),
  10 => Projected<int>(),
  11 => Box<Child>(),
  12 => Box<Base>(),
  13 => Box<FutureOr<int>>(),
  14 => Box<int Function(num)>(),
  _ => Box<({int n, bool b})>(),
};

void churn(int count) {
  for (var i = 0; i < count; i++) {
    Box<int>();
  }
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int classify(int mode, int seed, int count) {
  final object = value(mode, seed);
  churn(count);
  return (object is int ? 1 : 0) |
      (object is double ? 2 : 0) |
      (object is num ? 4 : 0) |
      (object is bool ? 8 : 0) |
      (object is int? ? 16 : 0) |
      (object is! Base ? 32 : 0) |
      (object is Child ? 64 : 0) |
      (object is Flag ? 128 : 0) |
      (object is Box<int> ? 256 : 0) |
      (object is Box<num> ? 512 : 0) |
      (object is Box<int?> ? 1024 : 0) |
      (object is Box<Object?> ? 2048 : 0) |
      (object is Box<Base> ? 4096 : 0) |
      (object is FutureOr<int> ? 8192 : 0) |
      (object is Box<FutureOr<num>> ? 16384 : 0) |
      (object is Box<num Function(int)> ? 32768 : 0) |
      (object is Box<int Function(Object)> ? 65536 : 0) |
      (object is Box<({num n, Object b})> ? 131072 : 0) |
      (object is! Box<({int other, bool b})> ? 262144 : 0);
}

@Export<Int64 Function(Int64, Int64)>()
int promoted(int mode, int seed) {
  final object = value(mode, seed);
  if (object is int) return object * 2;
  if (object is double) return object > 0 ? 3 : 4;
  if (object is bool) return object ? 5 : 6;
  return -1;
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int caught(int mode, int seed, int count) {
  final object = value(mode, seed);
  if (object == null) return -1;
  try {
    throw object;
  } on Box<num> {
    churn(count);
    return 1;
  } on Flag {
    return 2;
  } on Child {
    return 3;
  } on Base {
    return 4;
  } on int catch (number) {
    churn(count);
    return number * 2;
  } on double {
    return 6;
  } on bool {
    return 7;
  } catch (_) {
    return 8;
  }
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int castInteger(int mode, int seed, int count) {
  try {
    final number = value(mode, seed) as int;
    churn(count);
    return number;
  } on TypeError {
    return -999;
  }
}

@Export<Double Function(Int64, Int64, Int64)>()
double castDouble(int mode, int seed, int count) {
  try {
    final number = value(mode, seed) as double;
    churn(count);
    return number;
  } on TypeError {
    return -999.5;
  }
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int castKinds(int mode, int seed, int kind) {
  final object = value(mode, seed);
  try {
    if (kind == 0) return (object as int?) ?? 123;
    if (kind == 1) return (object as bool) ? 11 : 12;
    if (kind == 2) {
      final box = object as Box<num>;
      churn(40000);
      return box is Box<int> ? 21 : 22;
    }
    if (kind == 3) return object! is int ? 31 : 32;
    if (kind == 4) return (object as FutureOr<int?>)! is int ? 41 : 42;
    if (kind == 5) {
      final dynamic dynamicValue = object;
      final bool flag = dynamicValue;
      return flag ? 51 : 52;
    }
    if (kind == 6) return object as Never;
    if (kind == 8) return (object as int?)!;
    object as Never?;
    return 71;
  } on TypeError {
    return -999;
  }
}

Object? effectValue(int mode, Pointer<Int64> effects) {
  effects.value = effects.value * 10 + 1;
  return value(mode, 17);
}

int checkedEffect(int mode, Pointer<Int64> effects) =>
    effectValue(mode, effects) as int;

@Export<Int64 Function(Int64, Int64, Pointer<Int64>)>()
int castCleanup(int mode, int count, Pointer<Int64> effects) {
  try {
    try {
      final result = checkedEffect(mode, effects);
      effects.value = effects.value * 10 + 2;
      return result;
    } on TypeError {
      effects.value = effects.value * 10 + 3;
      churn(count);
      rethrow;
    } finally {
      effects.value = effects.value * 10 + 4;
    }
  } on Error {
    effects.value = effects.value * 10 + 5;
    return -999;
  } finally {
    effects.value = effects.value * 10 + 6;
  }
}

@Export<Int64 Function(Int64)>()
int dynamicThrow(int mode) {
  final dynamic object = value(mode, 17);
  try {
    throw object;
  } on TypeError {
    return 1;
  } on int {
    return 2;
  } catch (_) {
    return 3;
  }
}

Object boxedDouble(double value) => value;

@Export<Double Function(Double)>()
double castFloating(double value) => boxedDouble(value) as double;
