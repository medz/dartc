import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'closures.dart' show collect;

typedef Step = int Function(int, {int extra});

int add(int n, {int extra = 1}) => n + extra;

class Counter(int value) {
  int value = value;

  int add(int n, {int extra = 3}) => value + n + extra;
  int subtract(int n, {int extra = 2}) => value - n - extra;

  @override
  bool operator ==(Object other) => other is Counter;
  @override
  int get hashCode => 0;
}

class DoubleCounter(super.value) extends Counter {
  @override
  int add(int n, {int extra = 5}) => (value + n + extra) * 2;
  Step get parent => super.add;
}

Step? saved;

@Export<Int64 Function(Int64, Int64)>()
int methodCalls(int mode, int count) {
  final Counter counter = mode == 0 ? Counter(10) : DoubleCounter(10);
  final method = counter.add;
  final parent = DoubleCounter(10).parent;
  saved = method;
  counter.value = 20;
  collect(count);
  return method(1) * 10000 + saved!.call(2, extra: 7) * 100 + parent(3);
}

@Export<Int64 Function(Int64)>()
int methodIdentity(int count) {
  final first = Counter(10), second = Counter(10);
  final method = first.add, again = first.add, other = second.add;
  final child = DoubleCounter(10);
  final parent = child.parent;
  Function? absent;
  final Object notFunction = first;
  final unbound = add;
  collect(count);
  return (method == again ? 1 : 0) +
      (method != other ? 10 : 0) +
      (method != first.subtract ? 100 : 0) +
      (parent == child.parent ? 1000 : 0) +
      (parent != child.add ? 10000 : 0) +
      (method != absent ? 100000 : 0) +
      (method != notFunction ? 1000000 : 0) +
      (absent != method ? 10000000 : 0) +
      (method != unbound ? 100000000 : 0) +
      (unbound == add ? 1000000000 : 0);
}

class Box<T>(final T value) {
  T read() => value;
  U choose<U>(T first, U second) => second;
  U constrained<U extends T>(U value) => value;
}

class IntBox(super.value) extends Box<int>;

@Export<Int64 Function(Int64)>()
int genericMethods(int count) {
  final Box<num> box = IntBox(4);
  final read = box.read;
  final choose = box.choose;
  final constrained = Box<num>(4).constrained;
  collect(count);
  final Object actual = read;
  return read().toInt() * 10000 +
      choose<int>(2, 3) * 1000 +
      constrained<double>(2.5).toInt() * 100 +
      (actual is int Function() ? 10 : 0) +
      (choose == box.choose ? 1 : 0);
}

int events = 0;
void record(int n) => events = events * 10 + n;

class Sink() {
  void note(int value) => record(value);

  int accept(covariant int value) {
    record(8);
    return value;
  }

  int fail(int value) => throw value;
}

int consume(Object function, int next) => next;
int tick() {
  record(9);
  return 0;
}

@Export<Int64 Function(Int64)>()
int methodChecks(int count) {
  events = 0;
  final Box<num> box = IntBox(1);
  try {
    consume(box.constrained, tick());
  } on TypeError {
    record(1);
  } finally {
    record(2);
  }
  final sink = Sink();
  final Object method = sink.accept;
  final int Function(Object?) accept = method as int Function(Object?);
  final fail = sink.fail;
  final note = sink.note;
  collect(count);
  try {
    accept(1.5);
  } on TypeError {
    record(3);
  }
  try {
    fail(4);
  } on int catch (value) {
    record(value);
  } finally {
    record(5);
  }
  note(6);
  return events;
}
