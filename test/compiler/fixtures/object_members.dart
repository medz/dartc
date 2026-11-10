import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'member_calls.dart' show Trace;
import 'type_checks.dart' show churn;

abstract class View();

class Override(final Trace trace, final Type result, final int count)
    implements View {
  @override
  Type get runtimeType {
    trace.value++;
    churn(count);
    return result;
  }

  Type actual() => super.runtimeType;
}

class Child(super.trace, super.result, super.count) extends Override;

class Throwing(super.trace, super.result, super.count) extends Override {
  @override
  Type get runtimeType {
    trace.value++;
    churn(count);
    throw 41;
  }

  Type inherited() => super.runtimeType;
}

class FakeType(final Trace trace, final int count) implements Type {
  @override
  bool operator ==(Object other) {
    trace.value++;
    churn(count);
    if (other is bool) throw 42;
    return other is int || other is Type;
  }

  @override
  int get hashCode => 0;

  @override
  String toString() => 'FakeType';
}

class IdentityType() implements Type;

Type readType(Object? value) => value.runtimeType;
Type genericType<T>(T value) => value.runtimeType;
Type? optionalType(Object? value) => value?.runtimeType;
bool equal(Type? left, Object? right) => left == right;

int defaults(int count) {
  var flags = 0;
  if (readType(null) == Null) flags |= 1;
  if (readType(0x7fffffffffffffff) == int) flags |= 2;
  if (readType(-0.0) == double) flags |= 4;
  if (readType(true) == bool) flags |= 8;
  if (genericType<int>(4) == int) flags |= 16;
  if (optionalType(null) == null) flags |= 32;
  final type = readType(IdentityType());
  churn(count);
  if (type == IdentityType) flags |= 64;
  if (optionalType(1) == int) flags |= 128;
  return flags;
}

int getters(int count) {
  final trace = Trace();
  final child = Child(trace, int, count);
  final View value = child;
  var flags = 0;
  if (readType(value) == int) flags |= 1;
  if (genericType<View>(value) == int) flags |= 2;
  if (optionalType(value) == int) flags |= 4;
  if (value.runtimeType == int && trace.value == 4) flags |= 8;
  if (child.actual() == Child) flags |= 16;
  final Object(runtimeType: _) = value;
  if (trace.value == 5) flags |= 32;
  final matched = switch (value) {
    Object(runtimeType: == double) => 1,
    Object(runtimeType: == int) => 2,
    _ => 3,
  };
  if (matched == 2 && trace.value == 6) flags |= 64;
  if (Throwing(trace, int, count).inherited() == int && trace.value == 7) {
    flags |= 128;
  }
  return flags;
}

int customEquality(int count) {
  final trace = Trace(), getterTrace = Trace();
  final Type fake = FakeType(trace, count);
  final Object object = Override(getterTrace, fake, count);
  var flags = 0;
  if (object.runtimeType == int) flags |= 1;
  if (int != fake) flags |= 2;
  if (equal(fake, 7)) flags |= 4;
  if (!equal(fake, null) && !equal(null, fake) && trace.value == 2) flags |= 8;
  try {
    equal(fake, false);
  } on int catch (error) {
    if (error == 42) flags |= 16;
  } finally {
    churn(count);
  }
  if (equal(fake, int)) flags |= 32;
  if (!(fake != int)) flags |= 64;
  if (trace.value == 5 && getterTrace.value == 1) flags |= 128;
  return flags;
}

int identity(int count) {
  final Type first = IdentityType(), second = IdentityType();
  final same = first;
  churn(count);
  var flags = 0;
  if (first == same) flags |= 1;
  if (first != second) flags |= 2;
  if (first != int) flags |= 4;
  if (int != first) flags |= 8;
  if (!equal(first, 7)) flags |= 16;
  if (equal(null, null)) flags |= 32;
  if (equal(int, int)) flags |= 64;
  if (!equal(int, num)) flags |= 128;
  return flags;
}

int throwing(int count) {
  final trace = Trace();
  final Object value = Throwing(trace, int, count);
  var flags = 0;
  try {
    readType(value);
  } on int catch (error) {
    if (error == 41) flags |= 1;
  } finally {
    churn(count);
    if (trace.value == 1) flags |= 2;
  }
  if ((value as Throwing).inherited() == int && trace.value == 2) flags |= 4;
  return flags;
}

@Export<Int64 Function(Int64, Int64)>()
int objectMembers(int mode, int count) => switch (mode) {
  0 => defaults(count),
  1 => getters(count),
  2 => customEquality(count),
  3 => identity(count),
  _ => throwing(count),
};
