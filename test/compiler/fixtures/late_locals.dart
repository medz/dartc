import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show churn;

int binding(int count) {
  late final int? value;
  int? read() => value;
  void write(int? next) => value = next;
  var flags = 0, effects = 0;
  int next() => ++effects;
  try {
    read();
  } on Error {
    flags |= 1;
  }
  write(null);
  churn(count);
  if (read() == null) flags |= 2;
  try {
    write(next());
  } on Error {
    if (effects == 1 && read() == null) flags |= 4;
  }
  return flags;
}

int lazy(int count) {
  var attempts = 0, source = 3;
  int initialize() {
    churn(count);
    if (++attempts == 1) throw 19;
    return source;
  }

  late int value = initialize();
  int read() => value;
  var flags = 0;
  if (attempts == 0) flags |= 1;
  try {
    read();
  } on int catch (error) {
    if (error == 19) flags |= 2;
  }
  source = 5;
  if (read() == 5 && read() == 5 && attempts == 2) flags |= 4;
  late int bypassed = initialize();
  bypassed = 7;
  if (bypassed == 7 && attempts == 2) flags |= 8;
  return flags;
}

int recursive(int count) {
  late int Function() read;
  var depth = 0;
  int initialize() {
    final current = ++depth;
    churn(count);
    return current == 1 ? read() + 10 : 1;
  }

  late final int value = initialize();
  read = () => value;
  var flags = 0;
  try {
    read();
  } on Error {
    flags |= 1;
  }
  if (read() == 1 && depth == 2) flags |= 2;
  return flags;
}

int initializationWrites(int count, bool fail) {
  late void Function(int) write;
  int initialize() {
    write(4);
    churn(count);
    if (fail) throw 29;
    return 6;
  }

  late int value = initialize();
  write = (next) => value = next;
  var flags = 0;
  try {
    if (value == 6) flags |= 1;
  } on int catch (error) {
    if (error == 29) flags |= 1;
  }
  if (value == (fail ? 4 : 6)) flags |= 2;
  return flags;
}

int generic<T>(T seed, dynamic wrong, int count) {
  late final T value;
  void write(dynamic next) => value = next;
  var flags = 0;
  try {
    write(wrong);
  } on TypeError {
    flags |= 1;
  }
  write(seed);
  churn(count);
  try {
    write(wrong);
  } on TypeError {
    flags |= 2;
  }
  try {
    write(seed);
  } on Error {
    flags |= 4;
  }
  if (value == seed) flags |= 8;
  late T lazy = seed;
  T read() => lazy;
  if (read() == seed) flags |= 16;
  return flags;
}

int iterations(int count) {
  int Function()? first, second;
  for (var turn = 0; turn < 2; turn++) {
    final initial = turn;
    late int value = initial;
    if (turn == 0) {
      first = () => value;
    } else {
      second = () => value;
    }
  }
  churn(count);
  var flags = first!() == 0 && second!() == 1 ? 1 : 0;
  for (var turn = 0; turn < 2; turn++) {
    late int value;
    if (turn == 0) {
      first = () => value;
    } else {
      value = 9;
      second = () => value;
    }
  }
  churn(count);
  try {
    first!();
  } on Error {
    flags |= 2;
  }
  if (second!() == 9) flags |= 4;
  return flags;
}

int nullableAndNever(int count) {
  var calls = 0;
  int? initialize() {
    churn(count);
    calls++;
    return null;
  }

  late final int? value = initialize();
  int? read() => value;
  var flags = read() == null && read() == null && calls == 1 ? 1 : 0;
  Never fail() {
    calls++;
    throw 23;
  }

  late final Never never = fail();
  Never readNever() => never;
  for (var i = 0; i < 2; i++) {
    try {
      readNever();
    } on int catch (error) {
      if (error == 23) flags |= 2 << i;
    }
  }
  late Never unbound;
  if (count < 0) unbound = throw 23;
  Never readUnbound() => unbound;
  try {
    readUnbound();
  } on Error {
    if (calls == 3) flags |= 8;
  }
  return flags;
}

int Function()? saved;

int Function() escape(int count) {
  var source = 17;
  int initialize() {
    churn(count);
    return source;
  }

  late final int value = initialize();
  try {
    return () => value;
  } finally {
    source = 18;
  }
}

int retain(int count) {
  saved = escape(count);
  churn(count);
  return 1;
}

int representations(int count) {
  late double number = 2.5;
  late bool flag = true;
  late Pointer<Int64> pointer = Pointer.fromAddress(16);
  double readNumber() => number;
  bool readFlag() => flag;
  Pointer<Int64> readPointer() => pointer;
  churn(count);
  var flags = readNumber() == 2.5 && readFlag() && readPointer().address == 16
      ? 1
      : 0;
  number = -3.5;
  flag = false;
  pointer = Pointer.fromAddress(24);
  churn(count);
  if (readNumber() == -3.5 && !readFlag() && readPointer().address == 24) {
    flags |= 2;
  }
  return flags;
}

int recursiveMutable(int count) {
  late int Function() read;
  var depth = 0;
  int initialize() {
    final current = ++depth;
    churn(count);
    return current == 1 ? read() + 10 : 1;
  }

  late int value = initialize();
  read = () => value;
  return read() == 11 && read() == 11 && depth == 2 ? 1 : 0;
}

@Export<Int64 Function(Int64, Int64)>()
int lateLocals(int mode, int count) => switch (mode) {
  0 => binding(count),
  1 => lazy(count),
  2 => recursive(count),
  3 => initializationWrites(count, true) + initializationWrites(count, false),
  4 =>
    generic<int>(3, false, count) +
        generic<double>(2.5, false, count) +
        generic<bool>(true, 7, count),
  5 => iterations(count),
  6 => nullableAndNever(count),
  7 => retain(count),
  9 => representations(count),
  10 => recursiveMutable(count),
  _ => saved!(),
};
