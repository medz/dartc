// ignore_for_file: overridden_fields, unnecessary_null_comparison, use_primary_constructors, use_declaring_parameters, unnecessary_type_name_in_constructor, empty_catches
import 'dart:ffi';

import 'package:dartc/interop.dart';

class Base(final int seed) {
  int calls = 0;
  late int value = initialize();
  int initialize() {
    calls++;
    return seed;
  }
}

class Child extends Base {
  Child(super.seed);
  @override
  late int value = seed + 1;
  int readBase() => super.value;
  void writeBase(int next) {
    super.value = next;
  }
}

class Bound {
  late int value = -99;
  late final int fixed;
  Bound.formal(this.value, this.fixed);
  Bound.list(int seed) : value = seed, fixed = seed + 1;
}

@Export<Int64 Function()>()
int isolation() {
  final a = Child(10);
  final b = Child(20);
  final Base alias = a;
  if (a.calls != 0 || b.calls != 0) return -1;
  if (alias.value != 11 || a.readBase() != 10 || a.readBase() != 10) return -2;
  a.writeBase(30);
  alias.value = 40;
  if (a.value != 40 ||
      a.readBase() != 30 ||
      b.value != 21 ||
      b.readBase() != 20) {
    return -3;
  }
  if (a.calls != 1 || b.calls != 1) return -4;
  final skipped = Base(90);
  skipped.value = 0;
  if (skipped.value != 0 || skipped.calls != 0) return -5;
  final formal = Bound.formal(50, 51);
  final list = Bound.list(60);
  try {
    formal.fixed = 52;
    return -6;
  } on Error {}
  return formal.value + formal.fixed + list.value + list.fixed;
}

class Nullable() {
  late int? value;
  late final int? fixed;
  int calls = 0;
  late final int? initialized = initialize();
  int? initialize() {
    calls++;
    return null;
  }
}

@Export<Int64 Function()>()
int nullableBinding() {
  final box = Nullable();
  try {
    box.value;
    return -1;
  } on Error {}
  try {
    box.fixed;
    return -2;
  } on Error {}
  box.value = null;
  box.fixed = null;
  if (box.value != null || box.fixed != null) return -3;
  try {
    box.fixed = 1;
    return -4;
  } on Error {}
  if (box.initialized != null || box.initialized != null || box.calls != 1) {
    return -5;
  }
  box.value = 7;
  return box.fixed == null ? box.value! : -6;
}

class Initializers() {
  int retries = 0;
  int writes = 0;
  int mutableCalls = 0;
  int finalCalls = 0;
  late final int retry = initializeRetry();
  late int written = initializeWritten();
  late int recursive = initializeMutable();
  late final int fixed = initializeFinal();
  int initializeRetry() {
    if (++retries == 1) throw StateError('retry');
    return 72;
  }

  int initializeWritten() {
    writes++;
    written = 91;
    throw StateError('retain write');
  }

  int initializeMutable() {
    if (++mutableCalls == 1) return recursive + 10;
    recursive = 7;
    return recursive + 13;
  }

  int initializeFinal() {
    if (++finalCalls == 1) return fixed + 10;
    return 20;
  }
}

@Export<Int64 Function()>()
int initialization() {
  final box = Initializers();
  try {
    box.retry;
    return -1;
  } on StateError {}
  if (box.retry != 72 || box.retry != 72 || box.retries != 2) return -2;
  try {
    box.written;
    return -3;
  } on StateError {}
  if (box.written != 91 || box.written != 91 || box.writes != 1) return -4;
  if (box.recursive != 30 || box.recursive != 30 || box.mutableCalls != 2) {
    return -5;
  }
  try {
    box.fixed;
    return -6;
  } on TypeError {
    return -7;
  } on Error {}
  return box.fixed == 20 && box.finalCalls == 2 ? 1 : -8;
}

class FinalWrite() {
  late final int value;
  int effects = 0;
  dynamic rhs(int mode) {
    effects++;
    if (mode == 1) return false;
    if (mode == 2) throw StateError('RHS first');
    return 42;
  }
}

@Export<Int64 Function()>()
int writeOrdering() {
  final box = FinalWrite();
  try {
    box.value = box.rhs(1);
    return -1;
  } on TypeError {}
  box.value = box.rhs(0);
  try {
    box.value = box.rhs(0);
    return -2;
  } on TypeError {
    return -3;
  } on Error {}
  try {
    box.value = box.rhs(1);
    return -4;
  } on TypeError {}
  try {
    box.value = box.rhs(2);
    return -5;
  } on StateError {}
  return box.value * 10 + box.effects;
}

class GenericBase<T>(final dynamic input) {
  int calls = 0;
  late T value = initialize();
  T initialize() {
    calls++;
    return input as T;
  }
}

class GenericChild<A, B> extends GenericBase<B> {
  GenericChild(super.input);
  late final bool actualType = input is B && input is! A;
}

class GenericFinal<T>() {
  late final T value;
}

@Export<Int64 Function()>()
int genericEnvironment() {
  final good = GenericChild<double, int>(7);
  final other = GenericChild<int, double>(1.5);
  final GenericBase<num> bad = GenericChild<double, int>(1.5);
  if (!good.actualType ||
      !other.actualType ||
      good.value != 7 ||
      other.value != 1.5) {
    return -1;
  }
  for (var i = 0; i < 2; i++) {
    try {
      bad.value;
      return -2;
    } on TypeError {}
  }
  return bad.calls;
}

// Normative safety case, not SDK parity: SDK 3.13.7 omits this setter check.
@Export<Int64 Function()>()
int genericFinalSafety() {
  final GenericFinal<num> box = GenericFinal<int>();
  try {
    box.value = 1.5;
    return -1;
  } on TypeError {}
  box.value = 42;
  try {
    box.value = 1.5;
    return -2;
  } on TypeError {}
  return box.value as int;
}

class Cell(int initial, final Cell? next) {
  int value = initial;
}

void collect(int count) {
  Cell? tail;
  for (var i = 0; i < count; i++) {
    tail = Cell(i, tail);
  }
  if (tail != null && tail.value != count - 1) throw StateError('allocation');
}

class References(final int count) {
  final Cell token = Cell(11, null);
  int effects = 0;
  late final Cell value = initialize();
  late Cell failed = fail();
  Cell initialize() {
    final result = Cell(token.value, token);
    collect(count);
    token.value = 12;
    return result;
  }

  Cell fail() {
    failed = value;
    try {
      throw token;
    } on Cell catch (error) {
      collect(count);
      error.value = 13;
      effects = 1;
      rethrow;
    } finally {
      collect(count);
      effects = effects * 10 + 2;
    }
  }
}

@Export<Int64 Function(Int64)>()
int references(int count) {
  final box = References(count);
  final returned = box.value;
  collect(count);
  if (returned.value != 11 || returned.next!.value != 12) return -1;
  try {
    box.failed;
    return -2;
  } on Cell catch (error) {
    collect(count);
    error.value = 14;
    box.effects = box.effects * 10 + 3;
  } finally {
    collect(count);
    box.effects = box.effects * 10 + 4;
  }
  box.failed.value = 15;
  if (returned.value != 15 ||
      box.value.value != 15 ||
      returned.next!.value != 14 ||
      box.token.value != 14) {
    return -3;
  }
  return box.effects;
}
