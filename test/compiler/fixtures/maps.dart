import 'dart:collection';
import 'dart:ffi';

import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64)>()
int mapBasic(int count) {
  final map = <int, int>{1: 3, 2: 5};
  for (var i = 3; i <= count; i++) {
    map[i] = i;
  }
  var sum = 0;
  for (final key in map.keys) {
    sum += map[key]!;
  }
  return sum + map.length;
}

class _Key(final int id) {
  @override
  int get hashCode => 7;
  @override
  bool operator ==(Object other) => other is _Key && id == other.id;
}

@Export<Int64 Function()>()
int mapOrder() {
  final first = _Key(1);
  final map = <_Key, int>{first: 1, _Key(2): 2, _Key(3): 3};
  map[_Key(1)] = 9;
  if (!identical(map.keys.first, first)) return -1;
  if (map.remove(_Key(2)) != 2) return -2;
  map[_Key(2)] = 5;
  var result = 0;
  for (final key in map.keys) {
    result = result * 10 + key.id;
  }
  if (map.length != 3 || map[first] != 9 || map.remove(_Key(8)) != null) {
    return -3;
  }
  map.clear();
  return map.isEmpty && !map.containsKey(first) ? result : -4;
}

@Export<Int64 Function()>()
int mapNulls() {
  final map = <Object?, Object?>{null: null, 1: 'one'};
  map[1.0] = 'same';
  if (map.length != 2 || !map.containsKey(null) || map.containsKey(2)) {
    return -1;
  }
  if (map[null] != null || map[2] != null || map[1] != 'same') return -2;
  map[double.nan] = 4;
  map.clear();
  return map.length;
}

@Export<Int64 Function(Int64)>()
int mapChecked(int mode) {
  final original = <int, int>{1: 4};
  Map<Object?, Object?> map = original;
  try {
    if (mode == 0) {
      map['bad'] = 3;
    } else {
      map[1] = 'bad';
    }
    return -1;
  } on TypeError {
    return original.length * 10 + original[1]!;
  }
}

@Export<Int64 Function(Int64)>()
int mapIteration(int mode) {
  final map = <int, int>{1: 2, 3: 4};
  final keys = map.keys;
  map[5] = 6;
  final iterator = keys.iterator;
  if (keys.length != 3 ||
      !keys.contains(3) ||
      !iterator.moveNext() ||
      iterator.current != 1) {
    return -1;
  }
  switch (mode) {
    case 0:
      map[3] = 9;
    case 1:
      map[7] = 8;
    case 2:
      map.remove(3);
    case 3:
      map.remove(3);
      map[3] = 4;
    case 4:
      map.clear();
  }
  try {
    var sum = iterator.current;
    while (iterator.moveNext()) {
      sum += iterator.current;
    }
    if (iterator.moveNext()) return -2;
    return sum;
  } on ConcurrentModificationError {
    return 99;
  }
}

@Export<Int64 Function()>()
int mapAlgorithms() {
  // Exercises the public factory rather than a literal.
  // ignore: prefer_collection_literals
  final map = Map<int, int>();
  map[1] = 2;
  map.addAll(<int, int>{3: 4});
  map.putIfAbsent(1, () => 100);
  map.putIfAbsent(5, () => 6);
  map.update(3, (value) => value + 10);
  var sum = 0;
  map.forEach((key, value) {
    sum += key + value;
  });
  return sum;
}

var _failHash = false;
var _failEquals = false;

class _Throwing(final int id) {
  @override
  int get hashCode {
    if (_failHash) throw 41;
    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (_failEquals) throw 42;
    return other is _Throwing && other.id == id;
  }
}

@Export<Int64 Function(Int64)>()
int mapFailures(int mode) {
  _failHash = false;
  _failEquals = false;
  final map = <_Throwing, int>{_Throwing(1): 7};
  var result = 0;
  try {
    _failHash = mode == 0;
    _failEquals = mode == 1;
    map[_Throwing(2)] = 8;
    return -1;
  } on int catch (error) {
    result = error;
  } finally {
    _failHash = false;
    _failEquals = false;
    result += 100;
  }
  return result + map.length * 1000 + map[_Throwing(1)]!;
}

Map<int, _Key>? _saved;
@Export<Int64 Function(Int64)>()
int mapReferences(int count) {
  final map = <int, _Key>{};
  for (var i = 0; i < count; i++) {
    map[i] = _Key(i);
  }
  _saved = map;
  for (var i = 1; i < count; i += 2) {
    map.remove(i);
  }
  return map[0]!.id + map[count - 2]!.id + map.length;
}

@Export<Int64 Function()>()
int mapSaved() => _saved![2]!.id + _saved!.length;

class _Offset() extends MapBase<int, int> {
  final _values = <int, int>{};
  @override
  Iterable<int> get keys => _values.keys;
  @override
  int? operator [](Object? key) => _values[key];
  @override
  void operator []=(int key, int value) {
    _values[key] = value + 10;
  }

  @override
  int? remove(Object? key) => _values.remove(key);
  @override
  void clear() => _values.clear();
}

@Export<Int64 Function(Int64)>()
int mapDispatch(int mode) {
  final Map<int, int> map = mode == 0 ? <int, int>{} : _Offset();
  map[2] = 3;
  if (!map.containsKey(2)) return -1;
  final remove = map.remove;
  return switch (map) {
    {2: final value} => value + remove(2)!,
    _ => -2,
  };
}

@Export<Int64 Function()>()
int mapViews() => _inspectViews(<int, int>{1: 4, 2: 6});

int _inspectViews(Map<num, num> map) {
  final keys = map.keys;
  if (keys is! Iterable<int> || map is! LinkedHashMap<int, int>) return -1;
  var sum = 0;
  for (final entry in map.entries) {
    sum += entry.key.toInt() + entry.value.toInt();
  }
  for (final value in map.values) {
    sum += value.toInt();
  }
  return sum;
}

int _churn() {
  final values = <_Key>[];
  for (var i = 0; i < 12000; i++) {
    values.add(_Key(i));
  }
  return values[11999].id;
}

class _AllocatingKey(final int id) {
  @override
  int get hashCode => _churn() - 11999;
  @override
  bool operator ==(Object other) =>
      _churn() == 11999 && other is _AllocatingKey && other.id == id;
}

@Export<Int64 Function()>()
int mapCallbackRoots() {
  final first = _AllocatingKey(1);
  final map = <_AllocatingKey, _Key>{first: _Key(11)};
  map[_AllocatingKey(2)] = _Key(17);
  map[_AllocatingKey(1)] = _Key(23);
  if (!identical(map.keys.first, first)) return -1;
  return map.remove(_AllocatingKey(1))!.id + map[_AllocatingKey(2)]!.id;
}
