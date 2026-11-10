import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef BinaryNative = Int64 Function(Int64, Int64);

@Export<BinaryNative>()
int truncate(int left, int right) => left ~/ right;

@Export<BinaryNative>()
int modulo(int left, int right) => left % right;

@Export<BinaryNative>()
int remainder(int left, int right) => left.remainder(right);

@Export<BinaryNative>()
int divideCompound(int left, int right) {
  final saved = left ^ right;
  left ~/= right;
  left %= right;
  return left + saved;
}

@Export<Int64 Function()>()
int divisionType() {
  try {
    truncate(7, 0);
    // ignore: deprecated_member_use
  } on IntegerDivisionByZeroException catch (error) {
    // ignore: deprecated_member_use
    return error.runtimeType == IntegerDivisionByZeroException ? 1 : 0;
  }
  return -1;
}

@Export<BinaryNative>()
int divisionFailure(int value, int kind) {
  final state = _DivisionState();
  try {
    switch (kind) {
      case 0:
        state.next(value) ~/ state.next(0);
      case 1:
        state.next(value) % state.next(0);
      default:
        state.next(value).remainder(state.next(0));
    }
  } catch (error) {
    state.log = state.log * 10 + _classify(error);
  } finally {
    state.log = state.log * 10 + 4;
  }
  return state.log;
}

int _classify(Object error) =>
    (error is Exception ? 1 : 0) +
    (error is UnsupportedError ? 2 : 0) +
    (error is Error ? 4 : 0);

class _DivisionState() {
  int log = 0;

  int next(int value) {
    log = log * 10 + value;
    return value;
  }
}

@Export<BinaryNative>()
int multiply(int left, int right) => left * right;

@Export<BinaryNative>()
int bitAnd(int left, int right) => left & right;

@Export<BinaryNative>()
int bitOr(int left, int right) => left | right;

@Export<BinaryNative>()
int bitXor(int left, int right) => left ^ right;

@Export<Int64 Function(Int64)>()
int complement(int value) => ~value;

@Export<Int64 Function(Int64)>()
int same(int value) {
  final square = value * value;
  return (square & square) ^ (value | value) ^ (value ^ value);
}

@Export<BinaryNative>()
int overlap(int left, int right) {
  final product = left * right;
  return (product ^ left) | (product & right);
}

@Export<BinaryNative>()
int compound(int left, int right) {
  final original = left;
  left *= right;
  left &= ~right;
  left |= original;
  left ^= right;
  return left;
}

@Export<BinaryNative>()
int accumulate(int seed, int count) {
  var result = seed;
  for (var i = 0; i < count; i++) {
    final mask = ~result;
    final product = multiply(result, i + 1);
    result = bitXor(product, mask);
    if ((result & 1) == 0) {
      result |= seed;
    } else {
      result &= ~seed;
    }
  }
  return result;
}
