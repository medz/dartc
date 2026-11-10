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
  int get hashCode => throw 91;
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

bool objectEqual(Object? left, Object? right) => left == right;
int objectHash(Object? value) => value.hashCode;

@Export<Int64 Function(Int64)>()
int functionObjects(int count) {
  final first = Counter(10), second = Counter(10);
  final method = first.add, again = first.add;
  final Object erased = method;
  final Function function = method;
  int local(int value) => first.value + value;
  T generic<T>(T value) => value;
  final specialized = generic<int>, duplicate = generic<int>;
  final before = objectHash(erased), localHash = objectHash(local);
  final genericHash = objectHash(specialized);
  collect(count);
  var flags = 0;
  if (objectEqual(erased, again)) flags |= 1;
  if (!objectEqual(erased, second.add)) flags |= 2;
  if (objectHash(again) == before && function.hashCode == before) flags |= 4;
  if (objectHash(local) == localHash && objectEqual(local, local)) flags |= 8;
  if (objectEqual(specialized, duplicate) &&
      objectHash(duplicate) == genericHash) {
    flags |= 16;
  }
  if (objectEqual(add, add) && objectHash(add) == add.hashCode) flags |= 32;
  if (!objectEqual(erased, first) && !objectEqual(erased, 1)) flags |= 64;
  if (!objectEqual(1, erased) && !objectEqual(int, erased)) flags |= 128;
  if (!objectEqual(null, erased) && objectEqual(null, null)) flags |= 256;
  if (objectEqual(42, 42.0) && objectHash(42) == objectHash(42.0)) flags |= 512;
  if (objectHash(0) == objectHash(-0.0) && objectEqual(0, -0.0)) flags |= 1024;
  if (!objectEqual(double.nan, double.nan)) flags |= 2048;
  if (!objectEqual('x', erased) && objectEqual('x', 'x')) flags |= 4096;
  if (objectEqual(true, true) && !objectEqual(true, 1)) flags |= 8192;
  if (objectEqual(first, second) && !objectEqual(first, null)) flags |= 16384;
  try {
    objectHash(first);
  } on int catch (error) {
    if (error == 91) flags |= 32768;
  }
  final Object plain = Box<int>(3);
  if (plain != 1 && 1 != plain && plain != true && plain == plain) {
    flags |= 65536;
  }
  return flags;
}

@Export<Int64 Function(Int64, Double)>()
int scalarObjects(int number, double floating) {
  final Object integerView = number, doubleView = floating;
  var flags = 0;
  if ((integerView == floating) == (number == floating)) flags |= 1;
  if ((floating == integerView) == (number == floating)) flags |= 2;
  if ((doubleView == number) == (floating == number)) flags |= 4;
  if ((number == doubleView) == (floating == number)) flags |= 8;
  if (integerView.hashCode == number.hashCode) flags |= 16;
  if (doubleView.hashCode == floating.hashCode) flags |= 32;
  if (number != floating || integerView.hashCode == doubleView.hashCode) {
    flags |= 64;
  }
  if ((doubleView == doubleView) == (floating == floating)) flags |= 128;
  if (number == floating) flags |= 256;
  return flags;
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
