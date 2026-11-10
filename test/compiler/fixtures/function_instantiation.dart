import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'closures.dart' show collect;

typedef Identity = T Function<T>(T);
T identity<T>(T value) => value;
T Function(T) identityFor<T>() => identity<T>;
int phantom<T>([int value = 7]) => value;

int useIdentity(Identity generic, int count) {
  final explicit = generic<int>;
  final int Function(int) inferred = generic;
  final number = generic<num>;
  collect(count);
  return explicit(2) * 10000 +
      inferred(3) * 1000 +
      number(4).toInt() * 100 +
      (explicit == (identity<int>) ? 10 : 0) +
      (explicit == inferred &&
              explicit != number &&
              explicit == identityFor<int>()
          ? 1
          : 0);
}

int usePhantom(int Function<T>() generic) =>
    (generic<int> == (generic<int>) ? 1 : 0) +
    (generic<int> != (generic<num>) ? 10 : 0) +
    (generic<int> == (phantom<int>) ? 100 : 0) +
    (generic<int>)() * 1000;

@Export<Int64 Function(Int64)>()
int staticFunctions(int count) =>
    useIdentity(identity, count) * 1000 + usePhantom(phantom);

int Function<T>(int) counter(int value) {
  int next<T>(int n) => value += n;
  return next;
}

int Function(int) specialize<T>(int Function<U>(int) generic) => generic<T>;

@Export<Int64 Function(Int64)>()
int closures(int count) {
  final generic = counter(1), other = counter(1);
  final first = generic<int>, second = generic<num>;
  final lexical = specialize<int>(generic);
  collect(count);
  return (first == lexical ? 1000000 : 0) +
      first(2) * 100000 +
      second(3) * 10000 +
      (first == (generic<int>) ? 1000 : 0) +
      (first != second ? 100 : 0) +
      (first != (other<int>) ? 10 : 0) +
      first(1);
}

class Box<T>(final T value) {
  U choose<U>(T first, U second) => second;
  U limited<U extends num>(U value) => value;
  T Function(T, T) bind() => choose<T>;
}

typedef PhantomBox<T, S> = Box<T>;
const phantomBox = PhantomBox.new;

int useConstructor(Box<T> Function<T>(T) make) {
  final applied = make<int>;
  return applied(4).value * 100 +
      (applied == Box<int>.new ? 10 : 0) +
      (applied == (make<int>) ? 1 : 0);
}

int useAlias(Box<T> Function<T, S>(T) make) =>
    (make<int, String> == (make<int, String>) ? 1 : 0) +
    (make<int, String> != (make<int, bool>) ? 10 : 0) +
    (make<int, String> != Box<int>.new ? 100 : 0) +
    (make<int, String> == (phantomBox<int, String>) ? 1000 : 0);

@Export<Int64 Function(Int64)>()
int constructors(int count) {
  collect(count);
  return useConstructor(Box.new) * 1000 + useAlias(PhantomBox.new);
}

@Export<Int64 Function(Int64)>()
int methods(int count) {
  final box = Box<int>(2), other = Box<int>(2);
  final generic = box.choose;
  final first = generic<int>, second = generic<num>;
  final bounded = box.limited<double>;
  final fromOwner = box.bind();
  collect(count);
  var checked = 0;
  try {
    (first as int Function(Object?, int))(1.5, 2);
  } on TypeError {
    checked = 1;
  }
  final Object actual = first;
  return checked * 10000000 +
      (first == fromOwner ? 1000000 : 0) +
      first(1, 2) * 100000 +
      second(1, 3).toInt() * 10000 +
      bounded(4.5).toInt() * 1000 +
      (first == (box.choose<int>) ? 100 : 0) +
      (first != (other.choose<int>) ? 10 : 0) +
      (actual is int Function(Object?, int) ? 1 : 0);
}

int events = 0;
T throwing<T>(T value) {
  events = 2;
  throw value as Object;
}

int useThrow(Identity generic, int count) {
  final applied = generic<int>;
  collect(count);
  try {
    events = 1;
    applied(4);
  } on int catch (value) {
    events = events * 10 + value;
  } finally {
    events = events * 10 + 5;
  }
  return events;
}

@Export<Int64 Function(Int64)>()
int exceptions(int count) => useThrow(throwing, count);
