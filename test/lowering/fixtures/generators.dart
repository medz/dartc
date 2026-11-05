import 'effects.dart';

int checksum(Iterable<int> values) {
  var result = 0;
  for (final value in values) {
    result = result * 31 + value;
  }
  return result;
}

Iterable<int> counted(int start, int count) sync* {
  tick(100);
  try {
    for (var i = 0; i < count; i++) {
      yield tick(start + i);
      tick(200 + i);
    }
  } finally {
    tick(300);
  }
}

int lazyPhases() {
  final values = counted(tick(1), 2);
  tick(10);
  final iterator = values.iterator;
  tick(20);
  iterator.moveNext();
  return iterator.current;
}

int earlyStopAndRepeat() {
  final values = counted(1, 3);
  for (final value in values) {
    tick(value + 400);
    break;
  }
  tick(500);
  return checksum(values) + checksum(values);
}

int interleavedCaptures() {
  var outer = 0;
  Iterable<int Function()> values(int seed) sync* {
    var local = seed;
    yield () => ++local + ++outer + ++seed;
    yield () => ++local + ++outer + ++seed;
  }

  final sequence = values(0);
  final a = sequence.iterator, b = sequence.iterator;
  a.moveNext();
  b.moveNext();
  final first = a.current();
  final second = b.current();
  a.moveNext();
  final third = a.current();
  b.moveNext();
  return checksum([first, second, third, b.current(), outer]);
}

Iterable<int Function()> loopClosures() sync* {
  for (var i = 0; i < 4; i++) {
    yield () => i;
  }
}

int retainedLoopClosures() {
  final readers = <int Function()>[...loopClosures()];
  return checksum([for (final read in readers) read()]);
}

Iterable<int> cleanup(int mode) sync* {
  try {
    try {
      yield 1;
      if (mode == 1) return;
      if (mode == 2) throw 7;
      yield 2;
    } finally {
      yield 3;
      // ignore: control_flow_in_finally
      if (mode == 3) return;
      if (mode == 4) throw 8;
      tick(30);
    }
  } on int catch (error) {
    yield error;
  } finally {
    yield 9;
    tick(90);
  }
}

int finalizerTransfers(int mode) => checksum(cleanup(mode));

Iterable<int> recursive(int depth) sync* {
  yield depth;
  if (depth > 0) yield* recursive(depth - 1);
  yield depth + 10;
}

int nestedDelegation(int depth) => checksum(recursive(depth));

Iterable<int> dynamicDelegate(dynamic source) sync* {
  try {
    yield* source;
    tick(40);
  } on TypeError {
    yield 99;
  }
}

int delegationTypeCheck(int kind) {
  dynamic values = switch (kind) {
    0 => <Object>[],
    1 => <Object>[1],
    2 => <dynamic>[1],
    _ => <int>[1],
  };
  return checksum(dynamicDelegate(values));
}

class Protocol(final int failure) implements Iterable<int> {
  @override
  Iterator<int> get iterator {
    tick(50);
    if (failure == 0) throw 10;
    return Cursor(failure);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

class Cursor(final int failure) implements Iterator<int> {
  int index = 0;
  @override
  int get current {
    tick(70 + index);
    if (failure == 2 && index == 2) throw 30;
    return index;
  }

  @override
  bool moveNext() {
    tick(60 + index);
    index++;
    if (failure == 1 && index == 2) throw 20;
    return index <= 3;
  }
}

Iterable<int> delegatedProtocol(int failure) sync* {
  try {
    yield* Protocol(failure);
    tick(80);
  } on int catch (error) {
    yield error;
  } finally {
    tick(90);
  }
}

int delegationFailures(int failure) => checksum(delegatedProtocol(failure));

Iterable<T> singleton<T>(T value) sync* {
  yield value;
}

class Holder<T>(final T value) {
  Iterable<T> values({int count = 2}) sync* {
    for (var i = 0; i < count; i++) {
      yield value;
    }
  }

  Iterable<T> get items sync* {
    yield* values();
  }
}

Iterable<Iterable<T>> nestedGeneric<T>(T value) sync* {
  yield singleton(value);
}

int genericGenerators() {
  var result = checksum(Holder<int>(4).items);
  for (final values in nestedGeneric<int>(3)) {
    result += checksum(values);
  }
  Iterable<T> local<T>(T value) sync* {
    yield* singleton<T>(value);
  }

  result += checksum(local<int>(2));
  return result;
}

Object broadResult() sync* {
  yield 4;
}

Iterable<int>? nullableResult() sync* {
  yield 5;
}

int resultProtocols() {
  final broad = broadResult();
  if (broad is! Iterable<dynamic>) return -1;
  final values = nullableResult()!;
  return checksum([for (final value in broad) value as int]) + checksum(values);
}

Iterable<int> checkedYield(dynamic value) sync* {
  try {
    yield value;
  } on TypeError {
    yield 9;
  }
}

int individualYieldChecks(bool valid) =>
    checksum(checkedYield(valid ? 1 : 'x'));

int iteratorLifecycle() {
  final iterator = singleton<int>(4).iterator;
  var result = 0;
  try {
    result += iterator.current;
  } on TypeError {
    result += 1;
  }
  iterator.moveNext();
  result += iterator.current;
  if (iterator.moveNext()) result += 100;
  try {
    result += iterator.current;
  } on TypeError {
    result += 10;
  }
  if (iterator.moveNext()) result += 1000;
  return result;
}

int reentrantIterator() {
  late Iterator<int> iterator;
  Iterable<int> values() sync* {
    try {
      iterator.moveNext();
    } on StateError {
      yield 8;
    }
    yield 9;
  }

  iterator = values().iterator;
  var result = 0;
  while (iterator.moveNext()) {
    result = result * 31 + iterator.current;
  }
  return result;
}

Iterable<int> manyValues(int count) sync* {
  for (var i = 0; i < count; i++) {
    yield i;
  }
}

Iterable<int> emptyNever(bool protected) sync* {
  if (protected) {
    try {
      yield* const <Never>[];
    } finally {
      tick(11);
    }
  } else {
    yield* const <Never>[];
  }
  yield 7;
}

int neverDelegation(bool protected) => checksum(emptyNever(protected));

int dynamicIteration() {
  dynamic sequence = singleton<int>(4);
  dynamic iterator = sequence.iterator;
  final next = iterator.moveNext;
  var result = 0;
  if (next()) result += iterator.current as int;
  if (iterator.moveNext()) result += 100;
  final other = singleton<int>(5).iterator;
  final staticNext = other.moveNext;
  if (staticNext()) result += other.current;
  return result;
}

Iterable<int> rethrowAfterYield() sync* {
  StackTrace? original;
  try {
    try {
      throw 7;
    } catch (error, trace) {
      original = trace;
      yield 1;
      rethrow;
    }
  } on int catch (error, trace) {
    yield identical(original, trace) ? error : -1;
  }
}

int resumedRethrow() => checksum(rethrowAfterYield());

Iterable<int> delegateCleanup() sync* {
  try {
    yield* counted(1, 2);
  } finally {
    tick(600);
  }
}

int stoppedDelegation() {
  for (final value in delegateCleanup()) {
    return value;
  }
  return -1;
}

Iterable<int> empty() sync* {}
Iterable<int> failed() sync* {
  throw 7;
}

int terminalIterators() {
  var result = 0;
  final noValues = empty().iterator;
  if (noValues.moveNext()) result += 100;
  if (noValues.moveNext()) result += 100;
  final throwing = failed().iterator;
  tick(1);
  try {
    throwing.moveNext();
  } on int catch (error) {
    result += error;
  }
  if (throwing.moveNext()) result += 1000;
  return result;
}

Type generatorRuntimeType() => singleton<int>(1).runtimeType;
Type generatorIteratorRuntimeType() => singleton<int>(1).iterator.runtimeType;

Iterable<int?> nullableElements() sync* {
  yield null;
  yield 4;
}

int nullableCurrent() {
  final iterator = nullableElements().iterator;
  var result = iterator.current ?? 1;
  iterator.moveNext();
  result += iterator.current ?? 2;
  iterator.moveNext();
  result += iterator.current ?? 3;
  iterator.moveNext();
  return result + (iterator.current ?? 5);
}

Object? broadNullableResult() sync* {
  yield 4;
}

dynamic broadDynamicResult() sync* {
  yield 4;
}

Iterable<Never> neverElements() sync* {}

int generatorElementTypes(Object? value) =>
    (value is Iterable<int> ? 1 : 0) +
    (value is Iterable<dynamic> ? 2 : 0) +
    (value is Iterable<Object?> ? 4 : 0);

int broadSignatures() {
  return checksum([
    generatorElementTypes(broadResult()),
    generatorElementTypes(broadNullableResult()),
    generatorElementTypes(broadDynamicResult()),
    generatorElementTypes(neverElements()),
    generatorElementTypes(nullableResult()),
  ]);
}
