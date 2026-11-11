import 'dart:ffi';

import 'package:dartc/interop.dart';

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected member');
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
