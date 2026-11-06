// ignore_for_file: dead_code, unused_local_variable, curly_braces_in_flow_control_structures
import 'effects.dart';

// Only explicitly implemented members are used. The noSuchMethod stubs satisfy
// SDK interface checks and must never serve as dynamic dispatch in these tests.

class TraceList(final List<int> data, final int failure) implements List<int> {
  @override
  int get length {
    tick(10);
    if (failure == 1) throw 71;
    return data.length;
  }

  @override
  int operator [](int index) {
    tick(20 + index);
    if (failure == 2) throw 72;
    return data[index];
  }

  @override
  List<int> sublist(int start, [int? end]) {
    tick(30 + start);
    tick(end ?? 99);
    if (failure == 3) throw 73;
    return data.sublist(start, end);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

class TraceMap<V>(final Map<int, V> data, final int failure)
    implements Map<int, V> {
  @override
  V? operator [](Object? key) {
    tick(40 + (key as int));
    if (failure == 1) throw 81;
    return data[key];
  }

  @override
  bool containsKey(Object? key) {
    tick(50 + (key as int));
    if (failure == 2) throw 82;
    return data.containsKey(key);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int listShapes(int n) {
  Object value = <int>[for (var i = 0; i < n; i++) i + 1];
  return switch (value) {
    <int>[] => 10,
    <int>[var a] => a,
    <int>[var a, ...var middle, var z] => a * 100 + middle.length * 10 + z,
    _ => -1,
  };
}

int sublistArguments() {
  final items = [1, 2, 3];
  return items.sublist(1).length * 100 +
      items.sublist(1, null).length * 10 +
      items.sublist(1, 2).length;
}

int listWildcards(int n) {
  final value = TraceList(<int>[for (var i = 0; i < n; i++) i], 0);
  var result = 0;
  if (value case [...]) result += 1;
  if (value case [..._]) result += 2;
  if (value case [_, ...]) result += 4;
  if (value case [..., _]) result += 8;
  if (value case [_, _]) result += 16;
  if (value case []) result += 32;
  return result;
}

int listOrder(int failure) {
  try {
    final value = TraceList(<int>[1, 2, 3, 4], failure);
    if (value case [var first, ...var rest, var last])
      return first + rest[0] + last;
    return 0;
  } finally {
    tick(100);
  }
}

int listTailRest(int failure) {
  try {
    if (TraceList(<int>[1, 2, 3], failure) case [var first, ...var rest])
      return first + rest.length;
    return 0;
  } finally {
    tick(100);
  }
}

int listCaches(int seed) {
  final data = <int>[seed, 2];
  final value = TraceList(data, 0);
  bool mutate() {
    data[0] = 9;
    tick(70);
    return false;
  }

  return switch (value) {
    [var first, ...var rest] when mutate() => -10,
    [var first, ...var rest] => first * 10 + rest[0],
    _ => -1,
  };
}

int listLogical(int seed) {
  final value = TraceList(<int>[seed, 2], 0);
  if (value case [0, var a] || [var a, _]) return a;
  return -1;
}

int listPaths(int seed) => switch (TraceList(<int>[seed, 2], 0)) {
  [1, 0] => -1,
  [..., 2] && List(length: var n) => n,
  _ => 0,
};

int listRestCopy(int seed) {
  final source = <int>[seed, 2, 3];
  final [first, ...rest] = source;
  source[1] = 9;
  rest[0] = 7;
  Object erased = rest;
  return (erased is List<int> ? 1000 : 0) +
      source[1] * 100 +
      rest[0] * 10 +
      first;
}

int nestedCollections(int seed) {
  Object value = <Object?>[
    (
      seed,
      <String, Object?>{
        'a': <int>[2, 3],
      },
    ),
  ];
  if (value case [(int x, {'a': [var y, var z]})])
    return x + (y as int) + (z as int);
  return -1;
}

int mapShapes(int seed) {
  Object value = <int, int?>{if (seed != 0) 1: seed == 1 ? null : seed, 2: 4};
  return switch (value) {
    <int, int?>{1: int a, 2: var b} => a + b!,
    <int, int?>{1: null} => 10,
    Map<int, int?>() => 20,
    _ => -1,
  };
}

int mapOrder(int seed) {
  final value = TraceMap<int?>(<int, int?>{
    if (seed != 0) 1: seed == 1 ? null : seed,
    2: 4,
  }, 0);
  if (value case {1: var a, 2: var b}) return (a ?? 10) + b!;
  return -1;
}

int mapFailure(int failure) {
  try {
    if (TraceMap<int?>(<int, int?>{1: null}, failure) case {1: _}) return 1;
    return 0;
  } finally {
    tick(100);
  }
}

int mapNonnullable(int seed) {
  if (TraceMap<int>(<int, int>{if (seed != 0) 1: seed}, 2) case {1: _})
    return 1;
  return 0;
}

int mapCaches(int seed) {
  final data = <int, int?>{1: seed == 0 ? null : seed};
  final value = TraceMap<int?>(data, 0);
  bool mutate() {
    data[1] = 9;
    tick(70);
    return false;
  }

  return switch (value) {
    {1: var first} when mutate() => -10,
    {1: var first} => first ?? 20,
    _ => -1,
  };
}

int declarations(int seed) {
  final [a, b] = <int>[if (seed != 0) seed, 2];
  final {1: c} = <int, int>{if (seed != 1) 1: 4};
  return a + b + c;
}

int assignmentAtomic(int seed) {
  var a = 7;
  var b = 8;
  int read() => a * 10 + b;
  try {
    [a, b] = <int>[tick(1), if (seed != 0) tick(2)];
    {1: a, 2: b} = <int, int>{1: tick(3), if (seed != 1) 2: tick(4)};
  } on StateError {
    tick(90);
  }
  return read();
}

int patternLoops(int seed) {
  var result = 0;
  for (final [a, ...rest] in <List<int>>[
    <int>[seed, 2],
    <int>[3, 4],
  ]) {
    result += a + rest[0];
  }
  final callbacks = <int Function()>[
    for (final {1: a} in <Map<int, int>>[
      <int, int>{1: seed},
      <int, int>{1: 3},
    ])
      () => a,
  ];
  return result * 10 + callbacks[0]() + callbacks[1]();
}

int erasedPatterns(int seed) {
  dynamic value = seed == 0 ? <Object?>[1, 2] : <int>[1, 2];
  var result = 0;
  if (value case <int>[var a, var b]) result += a + b;
  if (value case [int a, int b]) result += 10 + a + b;
  List raw = <int>[1, 2];
  if (raw case [int a, int b]) result += 100 + a + b;
  return result;
}

class OddMap(final bool present, final int? returned)
    implements Map<int, int?> {
  @override
  int? operator [](Object? key) {
    tick(41);
    return returned;
  }

  @override
  bool containsKey(Object? key) {
    tick(51);
    return present;
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int inconsistentMap(int seed) {
  final value = OddMap(seed > 1, seed == 0 || seed == 2 ? null : 7);
  if (value case {1: var found}) return found ?? 10;
  return -1;
}

class OddLength(final int size) implements List<int> {
  @override
  int get length {
    tick(10);
    return size;
  }

  @override
  int operator [](int index) {
    tick(20 + index);
    return 1;
  }

  @override
  List<int> sublist(int start, [int? end]) {
    tick(30);
    return <int>[];
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int negativeLength(int seed) {
  final value = OddLength(seed);
  var result = 0;
  if (value case []) result += 1;
  if (value case [...]) result += 2;
  if (value case [...var rest]) result += 4 + rest.length;
  return result;
}

int listTypedRestWildcard(int seed) {
  if (TraceList(<int>[seed, 2, 3], 0) case [_, ...List<int> _]) return 1;
  return 0;
}

int mapLogical(int seed) {
  final value = TraceMap<int?>(<int, int?>{
    1: seed == 0 ? null : seed,
    2: 3,
  }, 0);
  if (value case {1: 0, 2: var a} || {1: var a}) return a ?? 10;
  return -1;
}

int listNullChecks(int seed) {
  Object? value = seed == 0 ? null : <int?>[seed == 1 ? null : seed];
  if (value case [int a!]?) return a;
  return -1;
}

int listCastFailure(int seed) {
  Object value = <Object?>[seed == 0 ? 'bad' : seed];
  if (value case [var a as int]) return a;
  return -1;
}

int nestedAssignmentAtomic(int seed) {
  var a = 7;
  var b = 8;
  try {
    (a, {1: b}) = (tick(1), <int, int>{if (seed != 0) 1: tick(2)});
  } on StateError {
    tick(90);
  }
  return a * 10 + b;
}

int genericPatterns(int seed) {
  int match<T>(List<T> list, Map<int, T> map) {
    Object value = list;
    if (value case <T>[var first, ...var rest]) {
      Object erased = rest;
      if (map case <int, T>{1: var found}) {
        return (erased is List<T> ? 100 : 0) +
            (first == found ? 10 : 0) +
            rest.length;
      }
    }
    return -1;
  }

  return match<int?>(
    <int?>[seed == 0 ? null : seed, 2],
    <int, int?>{if (seed != 2) 1: seed == 0 ? null : seed},
  );
}

int dynamicCollectionTypes(int seed) {
  Object value = seed == 0 ? <dynamic>[1, 2] : <int>[1, 2];
  Object map = seed == 0 ? <dynamic, dynamic>{1: 2} : <int, int>{1: 2};
  var result = 0;
  if (value case <int>[_, _]) result += 1;
  if (value case [int _, int _]) result += 2;
  if (map case <int, int>{1: _}) result += 4;
  if (map case {1: int _}) result += 8;
  return result;
}

int mismatchedCollections(int seed) {
  Object? value = seed == 0
      ? null
      : seed == 1
      ? 42
      : <String>['x'];
  if (value case <int>[var item]) return item;
  if (value case <int, int>{1: var item}) return item;
  return -1;
}

int castAssignmentAtomic(int seed) {
  var a = 7;
  var b = 8;
  dynamic value = <Object?>[1, seed == 0 ? 'bad' : 2];
  try {
    [a, b] = value;
  } on TypeError {
    tick(90);
  }
  return a * 10 + b;
}

int contextualDeclarations(int seed) {
  dynamic value = seed == 0 ? <Object?>[1, 2] : <int>[1, 2];
  final [int a, num b] = value;
  dynamic map = seed == 2 ? <Object?, Object?>{1: 3} : <int, int>{1: 3};
  final {1: int c} = map;
  return a + (b as int) + c;
}

int contextualNestedAssignment(int seed) {
  var a = 7, b = 8;
  dynamic value = (
    TraceList(<int>[1, 2], 0),
    seed == 0 ? <Object?>[1] : <int>[1],
  );
  try {
    (TraceList(length: a), [b]) = value;
  } on TypeError {
    tick(90);
  }
  return a * 10 + b;
}

int contextualMapAssignment(int seed) {
  var a = 7;
  dynamic value = seed == 0 ? <Object?, Object?>{1: 2} : <Object?, int>{1: 2};
  try {
    {1: a} = value;
  } on TypeError {
    tick(90);
  }
  return a;
}

int uncontextualPatternIteration(int seed) {
  final value = <Object?>[1];
  var result = 0;
  for (final [int a] in <dynamic>[value]) {
    result += a;
  }
  final elements = <int>[
    for (final [int a] in <dynamic>[value]) a,
  ];
  List<dynamic> typed = value;
  var a = 7;
  [a] = typed;
  return result + elements[0] + a;
}

int contextualRecordFields(int seed) {
  dynamic value = seed == 0 ? 'bad' : 3;
  final (int a, int b) = (value, tick(2));
  return a + b;
}
