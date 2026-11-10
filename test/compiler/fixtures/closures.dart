import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef Read = int Function();
typedef Step = int Function(int);

class Node(int initial, Node? previous) {
  int value = initial;
  Node? next = previous;
}

@Export<Int64 Function(Int64)>()
int collect(int count) {
  Node? tail;
  for (var i = 0; i < count; i++) {
    tail = Node(i, tail);
  }
  return tail == null ? -1 : tail.value;
}

Step? savedAdd;
Read? savedRead;

void createCounter(int start) {
  int add(int n) => start += n;
  int read() => start;
  savedAdd = add;
  savedRead = read;
}

@Export<Int64 Function(Int64, Int64)>()
int counter(int mode, int value) {
  if (mode == 0) createCounter(value);
  if (mode == 1) return savedAdd!(value);
  return savedRead!();
}

Step Function(int) nestedCounter(int base) {
  Step make(int bias) =>
      (int n) => base += n + bias;
  return make;
}

@Export<Int64 Function(Int64)>()
int nested(int count) {
  final make = nestedCounter(2);
  final first = make(1), second = make(4);
  collect(count);
  return first(3) * 100 + second(2) * 10 + first(0);
}

@Export<Int64 Function(Int64)>()
int recursive(int n) {
  int fact(int k) => k < 2 ? 1 : k * fact(k - 1);
  final Step saved = fact;
  return saved(n);
}

@Export<Int64 Function(Int64)>()
int iteration(int count) {
  Read? first, second, third;
  for (var i = 0; i < 3; i++) {
    int advance() => ++i;
    if (i == 0) first = advance;
    if (i == 1) second = advance;
    if (i == 2) third = advance;
  }
  collect(count);
  return first!() * 1000 + second!() * 100 + third!() * 10 + first();
}

Read capturedValues(int seed) {
  final immutable = seed;
  var object = Node(7, null);
  int? boxed = 9007199254740993;
  double floating = 1.25;
  bool flag = true;
  int read() {
    boxed = boxed! + 2;
    floating += 0.5;
    flag = !flag;
    object.value += 3;
    return (boxed! - 9007199254740993) * 1000 +
        object.value * 100 +
        floating.toInt() * 10 +
        immutable +
        (flag ? 1 : 0);
  }

  object = Node(11, object);
  return read;
}

@Export<Int64 Function(Int64)>()
int captures(int count) {
  final read = capturedValues(4);
  collect(count);
  final first = read();
  collect(count);
  return first * 10000 + read();
}

Read onExit(bool early) {
  var value = 2;
  try {
    if (early) return () => value;
    throw 7;
  } on int catch (error) {
    value += error;
    return () => value;
  } finally {
    value += 3;
  }
}

@Export<Int64 Function(Int64, Int64)>()
int afterExit(int early, int count) {
  final read = onExit(early != 0);
  collect(count);
  return read();
}

Read throwingCounter(Node node, int count) {
  var calls = 0;
  int read() {
    calls++;
    node.value += calls;
    collect(count);
    if (calls == 1) throw node;
    return node.value;
  }

  return read;
}

@Export<Int64 Function(Int64)>()
int invocationFailure(int count) {
  final node = Node(7, null);
  final read = throwingCounter(node, count);
  try {
    read();
    return -1;
  } on Node catch (error) {
    error.value += 10;
  } finally {
    collect(count);
    node.value += 3;
  }
  return read() * 100 + node.value;
}

T Function(T) typedIdentity<T>() {
  T identity(T value) => value;
  return identity;
}

class TypeOwner<T>() {
  bool Function(Object) make() =>
      (Object candidate) => candidate is T;
}

bool Function<U>(Object, U) genericCheck<T>(T captured) {
  bool check<U>(Object candidate, U value) =>
      candidate is T && value is T && captured is U;
  return check;
}

@Export<Int64 Function(Int64)>()
int generic(int count) {
  final identity = typedIdentity<int>();
  final floatingIdentity = typedIdentity<double>();
  final isInteger = TypeOwner<int>().make();
  final isFloating = TypeOwner<double>().make();
  final check = genericCheck<num>(7);
  final Object object = identity;
  final Object genericObject = check;
  collect(count);
  return identity(13) +
      (object is int Function(int) ? 16 : 0) +
      (object is num Function(int) ? 32 : 0) +
      (object is int Function(num) ? 0 : 64) +
      (object is double Function(double) ? 0 : 128) +
      (genericObject is bool Function<V>(Object, V) ? 256 : 0) +
      (check<int>(3, 4) ? 512 : 0) +
      (check<double>(3, 4.5) ? 0 : 1024) +
      (floatingIdentity(1.25) == 1.25 ? 2048 : 0) +
      (isInteger(7) && !isInteger(1.25) && isFloating(1.25) && !isFloating(7)
          ? 4096
          : 0);
}

@Export<Int64 Function(Int64)>()
int defaults(int base) {
  int positional(int n, [int extra = 3]) => base + n + extra;
  int named(int n, {int extra = 5, required int factor}) =>
      (base + n + extra) * factor;
  final int Function(int, [int]) first = positional;
  final int Function(int, {int extra, required int factor}) second = named;
  return first(2) +
      first(2, 7) * 10 +
      second(1, factor: 2) * 100 +
      second(1, factor: 3, extra: 4) * 10000;
}
