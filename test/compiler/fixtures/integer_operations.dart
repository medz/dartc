import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef BinaryNative = Int64 Function(Int64, Int64);

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
