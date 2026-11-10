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
