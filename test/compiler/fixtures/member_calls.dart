import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show churn;

class Trace([var int value = 0]) {
  int mark(int digit) => value = value * 10 + digit;
}

abstract class Action() {
  num call(int value, {int a = 1, int b = 2});
  Object get flag;
  int get state;
  set state(int value);
  int operator +(int value);
}

class Base(@override var int state, final int count) implements Action {
  @override
  bool get flag => true;

  @override
  int call(int value, {int a = 3, int b = 4, int c = 1}) {
    churn(count);
    return state + value + a * 10 + b + c;
  }

  @override
  int operator +(int value) => state + value;
}

class Child(super.state, super.count) extends Base {
  @override
  int call(int value, {int a = 5, int b = 6, int c = 2}) =>
      super.call(value, a: a, b: b, c: c) + 100;
}

mixin Offset on Base {
  @override
  int call(int value, {int a = 7, int b = 8, int c = 3}) =>
      super.call(value, a: a, b: b, c: c) + 200;
}

class Mixed(super.state, super.count) extends Base with Offset;

int defaults(int mode, int word, int count) {
  final Action action = switch (mode) {
    0 => Base(word, count),
    1 => Child(word, count),
    _ => Mixed(word, count),
  };
  final trace = Trace();
  final implicit = action.call(0);
  final explicit = action.call(0, b: trace.mark(1), a: trace.mark(2));
  action.state = 9;
  final operator = action + 4;
  if (action.flag is! bool) return -1;
  return (implicit is int ? implicit : -1) +
      (explicit is int ? explicit : -1) +
      trace.value +
      action.state +
      operator;
}

class Holder<T>(var T value, final int count) {
  T replace(T next) {
    churn(count);
    final previous = value;
    value = next;
    return previous;
  }

  Type bound<U extends T>() {
    churn(count);
    return U;
  }
}

int generic(int word, double number, int count) {
  final Holder<num> holder = Holder<int>(word, count);
  var flags = 0;
  try {
    holder.replace(number);
  } on TypeError {
    flags |= 1;
  } finally {
    churn(count);
    if ((holder.value as int) == word) flags |= 2;
  }
  try {
    holder.value = number;
  } on TypeError {
    flags |= 4;
  }
  try {
    holder.bound<num>();
  } on TypeError {
    flags |= 8;
  }
  if (int == holder.bound<int>() && (holder.replace(17) as int) == word) {
    flags |= 16;
  }
  if ((holder.value as int) == 17) flags |= 32;
  return flags;
}

abstract class Checked() {
  int put(covariant num value);
}

class Integers(final Trace trace, final int count) implements Checked {
  @override
  int put(int value) {
    churn(count);
    trace.mark(1);
    return value;
  }
}

int covariance(int word, double number, int count) {
  final trace = Trace();
  final Checked checked = Integers(trace, count);
  var flags = 0;
  try {
    checked.put(number);
  } on TypeError {
    if (trace.value == 0) flags |= 1;
  } finally {
    trace.mark(2);
  }
  if (checked.put(word) == word && trace.value == 21) flags |= 2;
  return flags;
}

abstract class Outcome() {
  num result();
}

class Fails() implements Outcome {
  @override
  Never result() => throw 42;
}

int throwing(int count) {
  final Outcome object = Fails();
  var flags = 0;
  try {
    object.result();
  } on int catch (error) {
    if (error == 42) flags |= 1;
  } finally {
    churn(count);
    flags |= 2;
  }
  try {
    Fails().result();
  } on int catch (error) {
    if (error == 42) flags |= 4;
  }
  return flags;
}

abstract class Floating() {
  num sum(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
    double g,
    double h,
    double i,
    double j, {
    int extra = 0,
  });
}

class Sum(final int count) implements Floating {
  @override
  double sum(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f,
    double g,
    double h,
    double i,
    double j, {
    int extra = 7,
  }) {
    churn(count);
    return a + b + c + d + e + f + g + h + i + j + extra;
  }
}

int floating(int count) {
  final Floating object = Sum(count);
  final result = object.sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
  return result is double && result == 62 ? 1 : 0;
}

abstract class Sink() {
  int put(Object? value, {int after = 0});
}

class EmptySink(final Trace trace) implements Sink {
  @override
  int put(covariant Never value, {int after = 0}) => trace.mark(9);
}

class GenericSink<T>(final Trace trace) {
  int put(T value) => trace.mark(9);
}

int neverParameters(int count) {
  final trace = Trace();
  final Sink sink = EmptySink(trace);
  var flags = 0;
  try {
    sink.put(trace.mark(1), after: trace.mark(2));
  } on TypeError {
    if (trace.value == 12) flags |= 1;
  }
  final callback = sink.put;
  try {
    callback(null, after: trace.mark(3));
  } on TypeError {
    if (trace.value == 123) flags |= 2;
  } finally {
    churn(count);
  }
  final GenericSink<Object?> generic = GenericSink<Never>(trace);
  try {
    generic.put(null);
  } on TypeError {
    if (trace.value == 123) flags |= 4;
  }
  return flags;
}

abstract class Producer<T>() {
  T produce();
}

class VoidProducer(final int count) implements Producer<void> {
  @override
  void produce() => Trace(41);

  void relay() {
    try {
      return produce();
    } finally {
      churn(count);
    }
  }
}

class VoidSlot(var void value);

void voidInteger(int value) => value + 1;
void voidDouble(double value) => -value;
void voidIdentity(void value) => value;
void voidEmpty() {}

int voidResults(int count) {
  final producer = VoidProducer(count);
  final Producer<Object?> view = producer;
  var flags = 0;
  if ((view.produce() as Trace).value == 41) flags |= 1;
  final Object? Function() relay = producer.relay;
  if ((relay() as Trace).value == 41) flags |= 2;
  final Object? Function(int) integer = voidInteger;
  if (integer(41) == 42) flags |= 4;
  final Object? Function(double) floating = voidDouble;
  if (1 / (floating(0.0) as double) == double.negativeInfinity) flags |= 8;
  void local() => Trace(43);
  void forwarded() => local();
  final Object? Function() callback = forwarded;
  if ((callback() as Trace).value == 43) flags |= 16;
  final Object? Function() empty = voidEmpty;
  if (empty() == null) flags |= 32;
  // ignore: void_checks
  final slot = VoidSlot(Trace(47));
  slot.value = voidIdentity(slot.value);
  if ((slot.value as Trace).value == 47) flags |= 64;
  return flags;
}

@Export<Int64 Function(Int64, Int64, Double, Int64)>()
int memberCalls(int mode, int word, double number, int count) => switch (mode) {
  < 3 => defaults(mode, word, count),
  3 => generic(word, number, count),
  4 => covariance(word, number, count),
  5 => throwing(count),
  6 => floating(count),
  7 => neverParameters(count),
  _ => voidResults(count),
};
