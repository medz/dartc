import 'dart:ffi';

import 'package:dartc/interop.dart';

int counter = 0;
double floating = -0.0;
bool flag = false;

// Unselected declarations need no storage, including unsupported types.
final int unusedFinal = 1;
late int unusedLate;
int? unusedNullable;
Object unusedReference = Object();

@Export<Int64 Function(Int64)>()
int writeCounter(int value) => counter = value;

@Export<Int64 Function()>()
int readCounter() => counter;

@Export<Int64 Function(Int64)>()
int addCounter(int value) => counter += value;

@Export<Double Function(Double)>()
double writeFloating(double value) => floating = value;

@Export<Double Function()>()
double readFloating() => floating;

@Export<Int64 Function(Int64)>()
int writeFlag(int value) {
  flag = value != 0;
  return flag ? 1 : 0;
}

@Export<Int64 Function()>()
int toggleFlag() {
  flag = !flag;
  return flag ? 1 : 0;
}

class First<T>() {
  static int counter = 11;
  int read() => counter;
  int write(int value) => counter = value;
}

class Second() {
  static int counter = 22;
}

@Export<Int64 Function(Int64, Int64)>()
int classState(int mode, int value) => switch (mode) {
  0 => First<int>().write(value),
  1 => First<double>().read(),
  2 => Second.counter = value,
  _ => Second.counter,
};

int lazyCalls = 0;
final int lazyValue = initializeLazy();
int initializeLazy() {
  lazyCalls++;
  return 42;
}

@Export<Int64 Function(Int64)>()
int lazyState(int mode) => mode == 0 ? lazyValue : lazyCalls;

int skippedCalls = 0;
// ignore: unnecessary_late
late int skippedValue = initializeSkipped();
int initializeSkipped() {
  skippedCalls++;
  return -1;
}

@Export<Int64 Function(Int64, Int64)>()
int skippedState(int mode, int value) => switch (mode) {
  0 => skippedValue = value,
  1 => skippedValue,
  _ => skippedCalls,
};

int retryCalls = 0;
// ignore: unnecessary_late
late final int retryValue = initializeRetry();
int initializeRetry() {
  retryCalls++;
  if (retryCalls == 1) throw StateError('retry');
  return 70 + retryCalls;
}

@Export<Int64 Function(Int64)>()
int retryState(int mode) {
  if (mode != 0) return retryCalls;
  try {
    return retryValue;
  } on StateError {
    return -1;
  }
}

int writtenCalls = 0;
// ignore: unnecessary_late
late int writtenValue = initializeWritten();
int initializeWritten() {
  writtenCalls++;
  writtenValue = 91;
  throw StateError('keep the write');
}

@Export<Int64 Function(Int64)>()
int writtenState(int mode) {
  if (mode != 0) return writtenCalls;
  try {
    return writtenValue;
  } on StateError {
    return -1;
  }
}

int recursiveCalls = 0;
// ignore: unnecessary_late
late int recursiveValue = initializeRecursive();
int initializeRecursive() {
  recursiveCalls++;
  if (recursiveCalls == 1) return recursiveValue + 10;
  recursiveValue = 7;
  return recursiveValue + 13;
}

@Export<Int64 Function(Int64)>()
int recursiveState(int mode) => mode == 0 ? recursiveValue : recursiveCalls;

class Cell(final int value, final Cell? previous);

int allocationCalls = 0;
final int allocatedValue = initializeAllocated();
int initializeAllocated() {
  allocationCalls++;
  final retained = Cell(42, null);
  var tail = retained;
  for (var i = 0; i < 40000; i++) {
    tail = Cell(i, tail);
  }
  return retained.value + tail.value;
}

@Export<Int64 Function(Int64)>()
int allocatedState(int mode) => mode == 0 ? allocatedValue : allocationCalls;

late int unboundInt;
late double unboundDouble;

class LateSlots() {
  static late bool flag;
  static late final double floating;
  static late final bool fixedFlag;
}

@Export<Int64 Function(Int64)>()
int lateState(int mode) {
  try {
    switch (mode) {
      case 0:
        return unboundInt;
      case 1:
        return unboundDouble == -0.0 ? 1 : 0;
      case 2:
        return LateSlots.flag ? 1 : 0;
      case 3:
        unboundInt = 0;
        unboundDouble = -0.0;
        LateSlots.flag = false;
        return 3;
      case 4:
        return 1.0 / LateSlots.floating == double.negativeInfinity ? 1 : 0;
      case 5:
        LateSlots.floating = -0.0;
        return 5;
      case 6:
        return LateSlots.fixedFlag ? 1 : 0;
      case 8:
        LateSlots.floating = 1.25;
        return 8;
      default:
        LateSlots.fixedFlag = true;
        return 7;
    }
  } on TypeError {
    return -2;
  } on StateError {
    return -3;
  } on Error {
    return -1;
  }
}

late final int boundOnce;
int rhsCalls = 0;
dynamic nextRhs(int mode) {
  rhsCalls++;
  if (mode == 2) return false;
  if (mode == 3) throw StateError('RHS first');
  return 42;
}

@Export<Int64 Function(Int64)>()
int finalWriteState(int mode) {
  if (mode == 4) return boundOnce;
  if (mode == 5) return rhsCalls;
  try {
    boundOnce = nextRhs(mode);
    return boundOnce;
  } on TypeError {
    return -2;
  } on StateError {
    return -3;
  } on Error {
    return -1;
  }
}

int finalRecursiveCalls = 0;
final int finalRecursiveValue = initializeFinalRecursive();
int initializeFinalRecursive() {
  finalRecursiveCalls++;
  if (finalRecursiveCalls == 1) return finalRecursiveValue + 10;
  return 20;
}

class FinalSlots() {
  static int calls = 0;
  // ignore: unnecessary_late
  static late final int value = initialize();
  static int initialize() {
    calls++;
    if (calls == 1) return value + 10;
    return 30;
  }

  static int throwingCalls = 0;
  static final int throwingValue = initializeThrowing();
  static int initializeThrowing() {
    throwingCalls++;
    if (throwingCalls == 1) {
      if (throwingValue == 40) throw StateError('inner value survives');
    }
    return 40;
  }
}

@Export<Int64 Function(Int64)>()
int finalRecursiveState(int mode) {
  try {
    return switch (mode) {
      0 => finalRecursiveValue,
      1 => finalRecursiveCalls,
      2 => FinalSlots.value,
      3 => FinalSlots.calls,
      4 => FinalSlots.throwingValue,
      _ => FinalSlots.throwingCalls,
    };
  } on StateError {
    return -2;
  } on TypeError {
    return -3;
  } on Error {
    return -1;
  }
}

late int neverBound;

@Export<Int64 Function(Int64)>()
int lateErrorCleanup(int count) {
  Object? retained;
  Object? retainedTrace;
  var effects = 0;
  var valid = true;
  try {
    try {
      return neverBound;
    } on Error catch (error, trace) {
      retained = error;
      retainedTrace = trace;
      valid = error is! TypeError && error is! StateError;
      effects = 1;
      try {
        for (var i = 0; i < count; i++) {
          try {
            return neverBound;
          } on Error catch (next) {
            if (next.runtimeType != retained.runtimeType ||
                next is TypeError ||
                next is StateError) {
              valid = false;
            }
          }
        }
        rethrow;
      } finally {
        effects = effects * 10 + 2;
      }
    }
  } on Error catch (error, trace) {
    valid =
        valid &&
        retained is Error &&
        retainedTrace is StackTrace &&
        error.runtimeType == retained.runtimeType &&
        trace.runtimeType == retainedTrace.runtimeType;
    effects = effects * 10 + 3;
  } finally {
    effects = effects * 10 + 4;
  }
  return valid ? effects : -1;
}
