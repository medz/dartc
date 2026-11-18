import 'dart:ffi';

import 'package:dartc/interop.dart';

class ScalarState<I extends int, F extends double, B extends bool>(
  I initialInteger,
  F initialFloating,
  B initialFlag,
) {
  I integer = initialInteger;
  F floating = initialFloating;
  B flag = initialFlag;
  late I lateInteger;
  late F lateFloating;
  late final B lateFlag;

  I readInteger(int depth) => integerRelay<I>(integer, depth);
  F readFloating(int depth) => floatingRelay<F, F>(floating, depth);
  B readFlag(int depth) => flagRelay<B>(flag, depth);

  Object observeInteger() => integer;
  Object observeFloating() => floating;
  Object observeFlag() => flag;
}

T integerRelay<T extends int>(T value, int depth) =>
    depth <= 0 ? value : integerRelay<T>(value, depth - 1);

T floatingRelay<U extends double, T extends U>(T value, int depth) =>
    depth <= 0 ? value : floatingRelay<U, T>(value, depth - 1);

T flagRelay<T extends bool>(T value, int depth) =>
    depth <= 0 ? value : flagRelay<T>(value, depth - 1);

bool integerEqual<T extends int>(T value, Object? other, int depth) =>
    depth <= 0 ? value == other : integerEqual<T>(value, other, depth - 1);

bool floatingEqual<T extends double>(T value, Object? other, int depth) =>
    depth <= 0 ? value == other : floatingEqual<T>(value, other, depth - 1);

bool flagEqual<T extends bool>(T value, Object? other, int depth) =>
    depth <= 0 ? value == other : flagEqual<T>(value, other, depth - 1);

bool promotedFlagEqual<T>(T value, Object? other) =>
    value is bool && value == other;

T relay<T>(T value, int depth) =>
    depth <= 0 ? value : relay<T>(value, depth - 1);

class Box<T>(final T value);

class NumberBox<T extends num>(final T value);

class Marker(final int value);
typedef IntRecord = (int,);

int observeInferredType<T>(T value) {
  if (value is int) {
    final box = Box(value);
    final record = (value,);
    final Type expected = Box<T>;
    return (box is Box<int> ? 1 : 0) |
        (record is (int,) ? 2 : 0) |
        (box.runtimeType == expected ? 4 : 0) |
        (record.runtimeType == IntRecord ? 8 : 0);
  }
  return 0;
}

@Export<Int64 Function(Int64, Int64)>()
int inferredType(int mode, int value) => switch (mode) {
  0 => observeInferredType<Object>(value),
  1 => observeInferredType<int>(value),
  _ => observeInferredType<Object>(value != 0),
};

ScalarState<int, double, bool>? _state;
Box<Object?>? _observed;
NumberBox<num>? _number;
Box<double?>? _nullable;

@Export<Int64 Function(Int64, Double, Int64, Int64)>()
int scalarEqual(int integer, double floating, int flag, int depth) {
  final other = _observed!.value;
  return (integerEqual(integer, other, depth) ? 1 : 0) |
      (floatingEqual(floating, other, depth) ? 2 : 0) |
      (flagEqual(flag != 0, other, depth) ? 4 : 0) |
      (promotedFlagEqual<Object>(flag != 0, other) ? 8 : 0);
}

@Export<Void Function(Int64, Double, Int64)>()
void storeScalars(int integer, double floating, int flag) {
  _state = ScalarState(integer, floating, flag != 0);
}

@Export<Int64 Function(Int64)>()
int readInteger(int depth) => _state!.readInteger(depth);

@Export<Double Function(Int64)>()
double readFloating(int depth) => _state!.readFloating(depth);

@Export<Int64 Function(Int64)>()
int readFlag(int depth) => _state!.readFlag(depth) ? 1 : 0;

@Export<Void Function(Int64, Double, Int64)>()
void replaceScalars(int integer, double floating, int flag) {
  final state = _state!;
  state.integer = integer;
  state.floating = floating;
  state.flag = flag != 0;
}

@Export<Void Function(Int64, Double, Int64)>()
void storeLateScalars(int integer, double floating, int flag) {
  final state = _state!;
  state.lateInteger = integer;
  state.lateFloating = floating;
  state.lateFlag = flag != 0;
}

@Export<Int64 Function()>()
int readLateInteger() => _state!.lateInteger;

@Export<Double Function()>()
double readLateFloating() => _state!.lateFloating;

@Export<Int64 Function()>()
int readLateFlag() => _state!.lateFlag ? 1 : 0;

@Export<Int64 Function()>()
int lateErrors() {
  var result = 0;
  try {
    _state!.lateInteger;
  } catch (_) {
    result |= 1;
  }
  try {
    _state!.lateFlag = false;
  } catch (_) {
    result |= 2;
  }
  return result;
}

class LateCell<T extends int>() {
  late T value;
}

@Export<Int64 Function(Int64, Int64)>()
int checkLateBound(int never, int value) {
  final LateCell<int> cell = never == 0 ? LateCell<int>() : LateCell<Never>();
  try {
    cell.value = value;
    return cell.value;
  } catch (_) {
    return -1;
  }
}

T Function(bool) captureInteger<T extends int>(T first, T second) {
  var current = first;
  return (replace) {
    if (replace) current = second;
    return current;
  };
}

T Function(bool) captureFloating<T extends double>(T first, T second) {
  var current = first;
  return (replace) {
    if (replace) current = second;
    return current;
  };
}

T Function(bool) captureFlag<T extends bool>(T first, T second) {
  var current = first;
  return (replace) {
    if (replace) current = second;
    return current;
  };
}

int Function(bool)? _integerCapture;
double Function(bool)? _floatingCapture;
bool Function(bool)? _flagCapture;

@Export<Void Function(Int64, Int64, Double, Double, Int64, Int64)>()
void storeCaptures(
  int firstInteger,
  int secondInteger,
  double firstFloating,
  double secondFloating,
  int firstFlag,
  int secondFlag,
) {
  _integerCapture = captureInteger(firstInteger, secondInteger);
  _floatingCapture = captureFloating(firstFloating, secondFloating);
  _flagCapture = captureFlag(firstFlag != 0, secondFlag != 0);
}

@Export<Int64 Function(Int64)>()
int capturedInteger(int replace) => _integerCapture!(replace != 0);

@Export<Double Function(Int64)>()
double capturedFloating(int replace) => _floatingCapture!(replace != 0);

@Export<Int64 Function(Int64)>()
int capturedFlag(int replace) => _flagCapture!(replace != 0) ? 1 : 0;

@Export<Void Function(Int64)>()
void observeScalar(int kind) {
  final state = _state!;
  final Object value = switch (kind) {
    0 => state.observeInteger(),
    1 => state.observeFloating(),
    _ => state.observeFlag(),
  };
  _observed = Box<Object?>(value);
}

@Export<Void Function(Int64, Int64, Double, Int64)>()
void storeMixed(int kind, int integer, double floating, int depth) {
  final Object? value = switch (kind) {
    0 => integer,
    1 => floating,
    2 => integer != 0,
    3 => null,
    _ => Marker(integer),
  };
  _observed = Box<Object?>(relay<Object?>(value, depth));
}

@Export<Int64 Function()>()
int observedKind() {
  final value = _observed!.value;
  if (value is int) return 0;
  if (value is double) return 1;
  if (value is bool) return 2;
  if (value == null) return 3;
  return value is Marker ? 4 : -1;
}

@Export<Int64 Function()>()
int observedInteger() {
  final value = _observed!.value;
  if (value is int) return value;
  if (value is bool) return value ? 1 : 0;
  return (value as Marker).value;
}

double promotedDouble<T>(T value) {
  if (value is double) return value;
  return -1.0;
}

@Export<Double Function()>()
double observedFloating() => promotedDouble(_observed!.value);

@Export<Void Function(Int64, Int64, Double)>()
void storeNumber(int kind, int integer, double floating) {
  final num value = kind == 0 ? integer : floating;
  _number = NumberBox<num>(value);
}

@Export<Int64 Function()>()
int numberKind() => _number!.value is int ? 0 : 1;

@Export<Double Function()>()
double numberValue() => _number!.value.toDouble();

@Export<Void Function(Int64, Double)>()
void storeNullable(int present, double value) {
  _nullable = Box<double?>(present == 0 ? null : value);
}

@Export<Int64 Function()>()
int nullablePresent() => _nullable!.value == null ? 0 : 1;

@Export<Double Function()>()
double nullableValue() => _nullable!.value!;

class PressureNode(final int value, final PressureNode? next);

PressureNode? _pressure;

@Export<Void Function(Int64)>()
void allocatePressure(int count) {
  PressureNode? head;
  for (var i = 0; i < count; i++) {
    head = PressureNode(i, head);
  }
  _pressure = head;
}

@Export<Int64 Function()>()
int pressureSum() {
  var sum = 0;
  for (var node = _pressure; node != null; node = node.next) {
    sum += node.value;
  }
  _pressure = null;
  return sum;
}
