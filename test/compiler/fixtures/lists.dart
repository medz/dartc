import 'dart:ffi';

import 'package:dartc/interop.dart';

const _constantLists = <List<int>>[
  [3, 5],
  [7],
];
List<List<int>>? _savedConstants;

@Export<Int64 Function(Int64, Int64, Int64)>()
int listSlice(int kind, int start, int end) {
  final List<int> source = switch (kind) {
    0 => <int>[1, 2, 3, 4],
    1 => 'A\u{1f600}Z'.codeUnits,
    4 => const <int>[1, 2, 3, 4],
    5 => List<int>.filled(4, 7),
    _ => _Custom(),
  };
  try {
    final List<int> result;
    if (kind == 3) {
      final slice = source.sublist;
      result = end == -1 ? slice(start) : slice(start, end == -2 ? null : end);
    } else {
      result = end == -1
          ? source.sublist(start)
          : source.sublist(start, end == -2 ? null : end);
    }
    var value = result.length;
    for (final item in result) {
      value = value * 10 + item;
    }
    return value;
  } on RangeError {
    return -1;
  }
}

@Export<Int64 Function(Int64, Int64)>()
int listCopy(int kind, int growable) {
  final List<Object?> source = switch (kind) {
    0 => <int>[3, 5],
    1 => <num>[3, 5],
    2 => <Object?>[3, 5],
    3 => <Object?>[3, 'bad'],
    4 => <int>[],
    _ => List<int>.filled(2, 4),
  };
  try {
    final dynamic input = source;
    final copy = kind <= 1
        ? List<int>.of(input, growable: growable != 0)
        : List<int>.from(source, growable: growable != 0);
    final length = copy.length;
    var value = length * 100;
    if (length != 0) {
      copy[0] = 9;
      value += copy[0] * 10 + (source[0] as int);
    }
    try {
      copy.add(7);
      return value + 1000;
    } on UnsupportedError {
      return value + 2000;
    }
  } on TypeError {
    return -1;
  }
}

@Export<Int64 Function(Int64, Int64)>()
int listCopyProtocol(int kind, int failure) {
  _iterationTrace = 0;
  try {
    final copy = kind == 0 ? List<int>.of : List<int>.from;
    copy(_Sequence(failure), growable: false);
    _iterationTrace = _iterationTrace * 10 + 4;
  } on StateError {
    _iterationTrace = _iterationTrace * 10 + 6;
  } finally {
    _iterationTrace = _iterationTrace * 10 + 5;
  }
  return _iterationTrace;
}

@Export<Int64 Function(Int64)>()
int listSliceMutability(int kind) {
  final List<num> source = switch (kind) {
    0 => const <int>[1, 2],
    1 => List<int>.filled(2, 4),
    2 => <int>[],
    _ => <int>[1, 2],
  };
  final result = source.sublist(0);
  if (result is! List<int> || identical(result, source)) return -1;
  result.add(3);
  final List<num> widened = result;
  try {
    widened.add(1.5);
  } on TypeError {
    return result.length * 10 + source.length;
  }
  return -2;
}

@Export<Int64 Function(Int64)>()
int listSlicePattern(int kind) {
  final source = switch (kind) {
    0 => <int>[1, 2, 3, 4],
    1 => <int>[1, 4],
    _ => <int>[1],
  };
  if (source case [final first, ...final middle, final last]) {
    middle.add(5);
    return first * 100 + last * 10 + middle.length;
  }
  return 0;
}

@Export<Int64 Function()>()
int listConstantOnly() => const <int>[3, 5][1];

@Export<Int64 Function(Int64)>()
int listConstants(int count) {
  const first = <int>[3, 5];
  _savedConstants = _constantLists;
  final hash = first.hashCode;
  var last = <int>[];
  for (var i = 0; i < count; i++) {
    last = <int>[i];
  }
  final values = _savedConstants!;
  return values[0][0] +
      values[1][0] +
      (identical(values[0], first) ? 10 : 0) +
      (first.hashCode == hash ? 20 : 0) +
      last.length;
}

@Export<Int64 Function(Int64)>()
int listConstMutation(int mode) {
  List<Object?> values = const <int>[3, 5];
  try {
    switch (mode) {
      case 0:
        values[0] = 9;
      case 1:
        values.add(9);
      case 2:
        values.length = 2;
      case 3:
        values[0] = 'bad';
      case 4:
        values[-1] = 9;
    }
  } on UnsupportedError {
    return values[0] as int;
  } on TypeError {
    return 10 + (values[0] as int);
  }
  return -1;
}

@Export<Int64 Function(Int64, Int64)>()
int listValues(int count, int mode) {
  final values = switch (mode) {
    0 => <int>[3, 5],
    1 => List<int>.empty(growable: true),
    _ => List<int>.filled(2, 4, growable: true),
  };
  for (var i = 0; i < count; i++) {
    values.add(i);
  }
  var total = 0;
  for (var i = 0; i < values.length; i++) {
    total += values[i];
  }
  return total;
}

@Export<Int64 Function(Int64, Int64)>()
int listFixed(int count, int index) {
  final values = List<int>.filled(count, 7);
  values[index] = 9;
  return values.length * 100 + values[index];
}

@Export<Int64 Function(Int64)>()
int listResize(int count) {
  final values = <int?>[1, 2, 3];
  values.length = 1;
  values.length = count;
  var total = 0;
  for (var i = 0; i < values.length; i++) {
    total += values[i] ?? 10;
  }
  return total;
}

List<T> _filled<T>(int count, T value) =>
    List<T>.filled(count, value, growable: true);
final class _Box(var int value);
List<_Box>? _saved;

List<T> _slice<T>(List<T> values) => values.sublist(0);

@Export<Int64 Function(Int64)>()
int listSliceReferences(int count) {
  final shared = _Box(17);
  final source = <_Box>[shared, _Box(2)];
  final copy = _slice(source);
  source[0] = _Box(3);
  shared.value = 29;
  copy.add(_Box(7));
  _saved = copy;
  for (var i = 0; i < count; i++) {
    _Box(i);
  }
  return copy.length * 100 + source[0].value * 10 + copy[0].value;
}

@Export<Int64 Function(Int64)>()
int listReferences(int count) {
  final shared = _Box(17);
  final values = _filled(3, shared);
  for (var i = 0; i < count; i++) {
    values.add(_Box(i));
  }
  shared.value = 23;
  _saved = values;
  var total = 0;
  for (var i = 0; i < values.length; i++) {
    total += values[i].value;
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int listSaved(int index) => _saved![index].value;

@Export<Int64 Function(Int64)>()
int listCycles(int count) {
  final values = <Object?>[];
  values.add(values);
  values.add(_Box(41));
  var last = _Box(0);
  for (var i = 0; i < count; i++) {
    last = _Box(i);
  }
  return identical(values, values[0])
      ? (values[1] as _Box).value + last.value
      : -1;
}

@Export<Int64 Function(Int64, Int64)>()
int listFailures(int mode, int index) {
  final integers = <int>[7];
  final List<num> numbers = integers;
  var result = 0;
  try {
    switch (mode) {
      case 0:
        List<int>.filled(index, 7);
      case 1:
        integers[index];
      case 2:
        integers[index] = 8;
      case 3:
        numbers[index] = 1.5;
      case 4:
        numbers.add(1.5);
      case 5:
        integers.length = 2;
      case 6:
        integers.length = index;
      case 7:
        List<int>.empty().add(7);
      case 8:
        List<int>.filled(1, 7).length = 1;
      case 9:
        final List<num> fixed = List<int>.filled(1, 7);
        fixed.add(1.5);
    }
  } on ArgumentError {
    result = 1;
  } on TypeError {
    result = 2;
  } on UnsupportedError {
    result = 3;
  } finally {
    result = result * 10 + integers[0];
  }
  return result;
}

final class _Custom() implements List<int> {
  int value = 90;
  @override
  int get length => 2;
  @override
  Iterator<int> get iterator => <int>[value, value + 1].iterator;
  @override
  int elementAt(int index) => this[index];
  @override
  List<int> sublist(int start, [int? end = 1]) => [
    value + start,
    end ?? length,
  ];
  @override
  set length(int value) {
    this.value = value;
  }

  @override
  int operator [](int index) => value + index;
  @override
  void operator []=(int index, int value) {
    this.value = value - index;
  }

  @override
  void add(int value) {
    this.value += value;
  }

  @override
  void addAll(Iterable<int> values) {
    for (final item in values) {
      value += item * 10;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected member');
}

@Export<Int64 Function(Int64, Int64)>()
int listIteration(int count, int mode) {
  final Iterable<int> values = switch (mode) {
    0 => List<int>.filled(count, 3),
    1 => const <int>[3, 5],
    _ => _Custom(),
  };
  var total = 0;
  for (final value in values) {
    total += value;
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int listIteratorMutation(int mode) {
  final values = <int>[1, 2];
  final iterator = values.iterator;
  final move = iterator.moveNext;
  move();
  if (mode == 0) values[1] = 9;
  if (mode == 1) values.add(3);
  if (mode == 2) values.length = 1;
  if (mode == 3) {
    values.add(3);
    values.length = 2;
  }
  try {
    return move() ? iterator.current : -1;
  } on ConcurrentModificationError {
    return 20;
  }
}

Iterator<int?>? _savedIterator;

@Export<Int64 Function(Int64)>()
int listIteratorState(int count) {
  final values = <int?>[null, 7];
  final iterator = values.iterator;
  if (!iterator.moveNext() || iterator.current != null) return -1;
  _savedIterator = iterator;
  for (var i = 0; i < count; i++) {
    _Box(i);
  }
  if (!iterator.moveNext()) return -2;
  return iterator.current!;
}

@Export<Int64 Function()>()
int listIteratorFinish() {
  final iterator = _savedIterator!;
  final current = iterator.current!;
  return !iterator.moveNext() && !iterator.moveNext() ? current : -1;
}

int _iterationTrace = 0;

final class _Sequence(final int failure) implements Iterable<int> {
  @override
  int get length => 2;
  @override
  int elementAt(int index) => index + 1;
  @override
  Iterator<int> get iterator {
    _iterationTrace = _iterationTrace * 10 + 1;
    return _Cursor(failure);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected member');
}

final class _Cursor(final int failure) implements Iterator<int> {
  int index = 0;
  @override
  bool moveNext() {
    _iterationTrace = _iterationTrace * 10 + 2;
    if (failure == 1 && index == 1) throw StateError('moveNext');
    if (index == 2) return false;
    index++;
    return true;
  }

  @override
  int get current {
    _iterationTrace = _iterationTrace * 10 + 3;
    if (failure == 2 && index == 2) throw StateError('current');
    return index;
  }
}

@Export<Int64 Function(Int64)>()
int iteratorProtocol(int failure) {
  _iterationTrace = 0;
  var total = 0;
  try {
    for (final value in _Sequence(failure)) {
      total += value;
      _iterationTrace = _iterationTrace * 10 + 4;
    }
  } on StateError {
    // The trace records the last completed operation.
  } finally {
    _iterationTrace = _iterationTrace * 10 + 5;
  }
  return _iterationTrace * 10 + total;
}

@Export<Int64 Function(Int64)>()
int listAppend(int mode) {
  final List<int> values = mode == 1 ? _Custom() : <int>[3];
  if (mode == 0) {
    values.addAll(const <int>[5, 7]);
  } else {
    final append = values.addAll;
    append(const <int>[5, 7]);
  }
  return values.length * 100 + values[0] + values[values.length - 1];
}

@Export<Int64 Function(Int64)>()
int listAppendFailures(int mode) {
  final List<num> values = switch (mode) {
    0 || 2 || 6 => List<int>.empty(),
    1 => const <int>[],
    _ => <int>[],
  };
  _iterationTrace = 0;
  try {
    switch (mode) {
      case 0 || 1:
        values.addAll(_Sequence(0));
      case 2 || 3:
        values.addAll(<num>[]);
      case 4:
        values.addAll(values);
      case 5:
        values.add(7);
        values.addAll(values);
      case 6:
        values.addAll(const <int>[]);
    }
  } on UnsupportedError {
    return 100 + _iterationTrace;
  } on TypeError {
    return 200 + _iterationTrace;
  } on ConcurrentModificationError {
    return 300 + values.length;
  }
  return values.length;
}

@Export<Int64 Function(Int64)>()
int listAppendProtocol(int failure) {
  _iterationTrace = 0;
  try {
    <int>[].addAll(_Sequence(failure));
  } on StateError {
    // The trace records the last completed iterator operation.
  } finally {
    _iterationTrace = _iterationTrace * 10 + 5;
  }
  return _iterationTrace;
}

int _spreadLast() {
  _iterationTrace = _iterationTrace * 10 + 4;
  return 9;
}

@Export<Int64 Function(Int64)>()
int listSpread(int mode) {
  final dynamic source = switch (mode) {
    0 => _Sequence(0),
    1 => <num>[1, 2],
    2 => <num>[1, 2.5],
    _ => null,
  };
  _iterationTrace = 0;
  try {
    final values = <int>[7, ...?source, _spreadLast()];
    return _iterationTrace * 100 +
        values.length * 10 +
        values[values.length - 1];
  } on TypeError {
    return 1000 + _iterationTrace;
  }
}

@Export<Int64 Function(Int64)>()
int listAppendReferences(int count) {
  final source = <_Box>[for (var i = 0; i < count; i++) _Box(i)];
  final values = <_Box>[...source];
  values.addAll(source);
  _saved = values;
  for (var i = 0; i < count; i++) {
    _Box(i);
  }
  var total = 0;
  for (final value in values) {
    total += value.value;
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int listDispatch(int mode) {
  final List<int> values = mode == 0 ? <int>[1, 2] : _Custom();
  final add = values.add;
  values[1] = 12;
  add(5);
  return values.length * 100 + values[1];
}

@Export<Int64 Function(Int64)>()
int listFactories(int count) {
  final factory = List<int>.filled;
  final values = factory(count, 3);
  return values.length * 10 + values[count - 1];
}

@Export<Double Function(Int64)>()
double listDoubles(int count) {
  final values = List<double>.filled(count, 0.5, growable: true);
  values.add(1.5);
  var total = 0.0;
  for (var i = 0; i < values.length; i++) {
    total += values[i];
  }
  return total;
}

@Export<Int64 Function(Int64)>()
int listOrder(int index) {
  var log = 0;
  final values = <int>[7];
  List<int> receiver() {
    log = log * 10 + 1;
    return values;
  }

  int key() {
    log = log * 10 + 2;
    return index;
  }

  int value() {
    log = log * 10 + 3;
    return 9;
  }

  try {
    receiver()[key()] = value();
  } on ArgumentError {
    log = log * 10 + 4;
  } finally {
    log = log * 10 + 5;
  }
  return log * 10 + values[0];
}
