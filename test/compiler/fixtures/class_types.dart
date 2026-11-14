import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show Box, churn;

Type typeOf<T>() => T;

bool sameValue(Object? a, Object? b) {
  if (a is int && b is int) return a == b;
  if (a is double && b is double) {
    return a != a ? b != b : a == b && 1 / a == 1 / b;
  }
  if (a is bool && b is bool) return a == b;
  return a.runtimeType == b.runtimeType;
}

class Pair<A, B>();

class Parent<A, B>(final A first, final B second, int count) {
  this {
    churn(count);
  }

  // ignore: avoid_shadowing_type_parameters
  Type pair<A>() => Pair<B, A>;

  bool hasTypes(Type first, Type second) => A == first && B == second;
}

class Child<T>(T value, int count) extends Parent<Box<T>, T?> {
  this : super(Box<T>(), value, count) {
    if (super.first.runtimeType != (Box<T>) ||
        (Pair<T?, T>) != super.pair<T>() ||
        !sameValue(super.second, value)) {
      throw 1;
    }
  }
}

class Factory<T>.internal() {
  factory(T value, int count) => Product<T>(value, count);
}

class Product<T>(final T value, int count) extends Factory<T> {
  this : super.internal() {
    churn(count);
    if (T != typeOf<T>()) throw 2;
  }
}

class Stack<T>(
  final T a,
  final T b,
  final T c,
  final T d,
  final T e,
  final T f,
  final T g,
  final T h,
  final T i,
  final T j,
  final double number,
  int count,
) {
  this {
    churn(count);
  }
}

class InspectStack<T>(T item, double number, int count) extends Stack<T> {
  this
    : super(
        item,
        item,
        item,
        item,
        item,
        item,
        item,
        item,
        item,
        item,
        number,
        count,
      ) {
    if (!sameValue(super.a, item) ||
        !sameValue(super.j, item) ||
        !sameValue(super.number, number)) {
      throw 3;
    }
  }
}

int construct<T>(T value, double number, int count) {
  final Object child = Child<T>(value, count);
  final factory = Factory<T>(value, count);
  final stack = InspectStack<T>(value, number, count);
  churn(count);
  if (!(child as dynamic).hasTypes(Box<T>, typeOf<T?>())) throw 4;
  return (child.runtimeType == (Child<T>) ? 1 : 0) |
      (child is Parent<Box<T>, T?> ? 2 : 0) |
      (factory.runtimeType == (Product<T>) ? 4 : 0) |
      (stack.runtimeType == (InspectStack<T>) ? 8 : 0);
}

@Export<Int64 Function(Int64, Int64, Double, Int64)>()
int classTypes(int mode, int word, double number, int count) => switch (mode) {
  0 => construct<int>(word, number, count),
  1 => construct<double>(number, number, count),
  2 => construct<int?>(null, number, count),
  3 => construct<Box<int>>(Box<int>(), number, count),
  4 => construct<bool>(true, number, count),
  _ => construct<Object?>(null, number, count),
};
