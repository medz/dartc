import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'closures.dart' show collect;

typedef Step = int Function(int, {int extra});

int add(int value, {int extra = 7}) => value + extra;
int subtract(int value, {int extra = 3}) => value - extra;
T identity<T>(T value) => value;
T bounded<T extends num>(T value) => value;

class const Holder(final Step step) {
  static int multiply(int value, {int extra = 2}) => value * extra;
}

const holder = Holder(add);
Step? saved;

int apply(int value, [Step step = add]) => step(value);

@Export<Int64 Function(Int64, Int64)>()
int staticCalls(int mode, int count) {
  final operation = switch (mode) {
    0 => add,
    1 => subtract,
    _ => Holder.multiply,
  };
  saved = operation;
  collect(count);
  return saved!(10) * 10000 +
      operation.call(9, extra: 4) * 100 +
      holder.step(2) * 10 +
      apply(1);
}

@Export<Int64 Function(Int64)>()
int staticIdentity(int count) {
  final first = add, second = Holder.multiply;
  collect(count);
  return (first == add ? 1 : 0) +
      (first != second ? 10 : 0) +
      (holder.step == first ? 100 : 0) +
      (first.call == first ? 1000 : 0);
}

@Export<Int64 Function(Int64)>()
int genericCalls(int count) {
  final generic = identity;
  final specialized = identity<int>;
  final int Function(int) inferred = identity;
  final number = bounded<double>;
  collect(count);
  return generic<int>(2) * 1000 +
      specialized(3) * 100 +
      inferred(4) * 10 +
      number(5.5).toInt();
}

@Export<Int64 Function(Int64)>()
int functionTypes(int count) {
  final Object generic = identity, specialized = identity<int>;
  final first = identity<int>, second = identity<double>;
  collect(count);
  return (generic is T Function<T>(T) ? 1 : 0) +
      (generic is! int Function(int) ? 10 : 0) +
      (specialized is num Function(int) ? 100 : 0) +
      (specialized is! double Function(double) ? 1000 : 0) +
      (first == (identity<int>) ? 10000 : 0) +
      // ignore: unrelated_type_equality_checks
      (first != second ? 100000 : 0);
}

class Box<T>(final T value);

typedef IntBox = Box<int>;
typedef RenameBox<T> = Box<T>;
typedef NumericBox<T extends num> = Box<T>;

abstract class Ticket() {
  factory create({int value}) = Product;
  int get value;
}

class Product({@override final int value = 6}) implements Ticket;

@Export<Int64 Function(Int64)>()
int constructors(int count) {
  final generic = Box.new;
  final explicit = Box<int>.new, alias = IntBox.new;
  final numeric = NumericBox.new;
  final factory = Ticket.create;
  collect(count);
  final first = generic<int>(2), second = explicit(3), third = alias(4);
  final ticket = factory();
  collect(count);
  return first.value * 10000 +
      second.value * 1000 +
      third.value * 100 +
      ticket.value * 10 +
      factory(value: numeric<int>(5).value).value;
}

@Export<Int64 Function(Int64)>()
int constructorIdentity(int count) {
  final first = Box<int>.new, second = IntBox.new;
  collect(count);
  return (first == second ? 1 : 0) +
      (first == Box<int>.new ? 10 : 0) +
      (Ticket.create != Product.new ? 100 : 0) +
      (Box.new == RenameBox.new ? 1000 : 0) +
      (Box.new != NumericBox.new ? 10000 : 0);
}

int events = 0;
void record(int value) => events = events * 10 + value;
int fail(int value) {
  record(2);
  throw value;
}

@Export<Int64 Function(Int64)>()
int effects(int count) {
  events = 0;
  final write = record, thrower = fail;
  var result = 0;
  try {
    write(1);
    write(thrower(9));
  } on int catch (error) {
    write(3);
    collect(count);
    result = error;
  } finally {
    write(4);
  }
  return events * 100 + result;
}
