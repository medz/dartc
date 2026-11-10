import 'dart:ffi';

import 'package:dartc/interop.dart';

int counter = 0;
double floating = -0.0;
bool flag = false;

// Unsupported storage must not block unrelated reachable exports.
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
int lazyValue = initializeLazy();
int initializeLazy() {
  lazyCalls++;
  return 42;
}

@Export<Int64 Function(Int64)>()
int lazyState(int mode) => mode == 0 ? lazyValue : lazyCalls;

int skippedCalls = 0;
int skippedValue = initializeSkipped();
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
int retryValue = initializeRetry();
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
int writtenValue = initializeWritten();
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
int recursiveValue = initializeRecursive();
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
int allocatedValue = initializeAllocated();
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
