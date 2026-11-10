import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef BinaryNative = Int64 Function(Int64, Int64);

@Export<BinaryNative>()
int shiftLeft(int value, int count) => value << count;

@Export<BinaryNative>()
int shiftRight(int value, int count) => value >> count;

@Export<BinaryNative>()
int unsignedShiftRight(int value, int count) => value >>> count;

@Export<BinaryNative>()
int shiftCompound(int value, int count) {
  final original = value;
  value <<= count;
  value >>= count;
  value >>>= count;
  return value ^ original;
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int shiftFailure(int value, int count, int kind) {
  final state = _DivisionState();
  var message = 0;
  try {
    switch (kind) {
      case 0:
        state.next(value) << state.next(count);
      case 1:
        state.next(value) >> state.next(count);
      default:
        state.next(value) >>> state.next(count);
    }
  } on ArgumentError catch (error) {
    final Object? payload = error.message;
    if (payload is! int ||
        error.name != null ||
        error.invalidValue != null ||
        error.runtimeType != ArgumentError) {
      return 12345;
    }
    message = payload;
    state.log = state.log * 10 + 3;
  } finally {
    state.log = state.log * 10 + 4;
  }
  return state.log ^ message;
}

@Export<BinaryNative>()
int argumentErrors(int message, int value) {
  final override = _UserArgumentError(value);
  final result =
      _errorValue(ArgumentError(message)) +
      _errorValue(ArgumentError.value(value)) +
      _errorValue(override);
  return result ^ override.reads;
}

int _errorValue(ArgumentError error) {
  final Object? message = error.message, value = error.invalidValue;
  if (message is int) return message;
  return value is int ? value : 0;
}

class _UserArgumentError(final int value) implements ArgumentError {
  int reads = 0;

  @override
  int get message {
    reads++;
    return value;
  }

  @override
  Object? get invalidValue => null;

  @override
  String? get name => null;

  @override
  StackTrace? get stackTrace => null;
}

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
