import 'dart:ffi';

import 'package:dartc/interop.dart';

class Cell(int initial, Cell? previous) {
  int value = initial;
  Cell? next = previous;
}

Cell? root;
Cell? alias;

@Export<Int64 Function(Int64)>()
int collect(int count) {
  Cell? tail;
  for (var i = 0; i < count; i++) {
    tail = Cell(i, tail);
  }
  return tail == null ? -1 : tail.value;
}

@Export<Int64 Function(Int64)>()
int graph(int mode) {
  if (mode == 0) return root == null && alias == null ? 1 : 0;
  if (mode == 1) {
    final head = Cell(11, null);
    head.next = Cell(22, head);
    root = head;
    alias = head;
  }
  final head = root;
  final other = alias;
  if (head == null || other == null) return -1;
  if (mode == 2) other.value += 7;
  final child = head.next;
  if (child == null) return -2;
  final cycle = child.next;
  if (cycle == null) return -3;
  return head.value + other.value + child.value + cycle.value;
}

num number = 0;
int? integer;
double? floating;
bool? flag;

@Export<Void Function(Int64)>()
void writeInteger(int value) {
  number = value;
  integer = value;
}

@Export<Int64 Function()>()
int readInteger() =>
    number is int && integer != null && (number as int) == integer!
    ? number as int
    : -1;

@Export<Void Function(Double)>()
void writeDouble(double value) {
  number = value;
  floating = value;
}

@Export<Double Function()>()
double readDouble() =>
    number is double &&
        floating != null &&
        1.0 / (number as double) == 1.0 / floating!
    ? number as double
    : 1.0;

@Export<Int64 Function(Int64)>()
int nullableState(int mode) {
  if (mode == 1) flag = false;
  if (mode == 2) flag = true;
  if (mode == 3) {
    integer = null;
    floating = null;
    flag = null;
  }
  return (integer == null ? 1 : 0) +
      (floating == null ? 2 : 0) +
      (flag == null ? 4 : (flag! ? 8 : 0));
}

int lazyCalls = 0;
final Cell lazy = initializeLazy();
Cell initializeLazy() {
  lazyCalls++;
  collect(40000);
  return Cell(42, null);
}

late Cell unbound;
late final Cell? once;

@Export<Int64 Function(Int64)>()
int binding(int mode) {
  try {
    switch (mode) {
      case 0:
        return lazy.value;
      case 1:
        return lazyCalls;
      case 2:
        return unbound.value;
      case 3:
        unbound = Cell(17, null);
        return unbound.value;
      case 4:
        return once == null ? 1 : 0;
      case 5:
        once = null;
        return 5;
      default:
        once = Cell(99, null);
        return 6;
    }
  } on Error {
    return -1;
  }
}

int retryCalls = 0;
// ignore: unnecessary_late
late final Cell retry = initializeRetry();
Cell initializeRetry() {
  retryCalls++;
  collect(40000);
  if (retryCalls == 1) throw StateError('retry');
  return Cell(72, null);
}

int writtenCalls = 0;
// ignore: unnecessary_late
late Cell written = initializeWritten();
Cell initializeWritten() {
  writtenCalls++;
  written = Cell(91, null);
  collect(40000);
  throw StateError('keep the write');
}

int recursiveCalls = 0;
final Cell recursive = initializeRecursive();
Cell initializeRecursive() {
  recursiveCalls++;
  if (recursiveCalls == 1) {
    final inner = recursive;
    collect(40000);
    return Cell(inner.value + 10, inner);
  }
  return Cell(20, null);
}

@Export<Int64 Function(Int64)>()
int initialization(int mode) {
  try {
    return switch (mode) {
      0 => retry.value,
      1 => retryCalls,
      2 => written.value,
      3 => writtenCalls,
      4 => recursive.value,
      _ => recursiveCalls,
    };
  } on StateError {
    return -2;
  } on Error {
    return -1;
  }
}

void main() {
  if (graph(0) != 1 || graph(1) != 55) throw StateError('initial graph');
  for (var i = 1; i <= 3; i++) {
    collect(40000);
    if (graph(2) != 55 + 21 * i) throw StateError('relocated graph');
  }
}
