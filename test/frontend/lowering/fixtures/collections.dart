// ignore_for_file: equal_elements_in_set, prefer_function_declarations_over_variables

int sum(List<int> values) {
  var result = 0;
  for (final value in values) {
    result += value;
  }
  return result;
}

int literal(bool choose, int? maybe, List<int>? more) {
  final values = <int>[1, if (choose) 2 else 3, ?maybe, ...?more];
  return sum(values);
}

int setLiteral() {
  final values = <int>{
    1,
    1,
    2,
    ...<int>[2, 3],
  };
  return values.length * 10 + sum(<int>[for (final v in values) v]);
}

int mapLiteral(int? key, int? value) {
  final values = <int, int>{
    1: 2,
    ...<int, int>{2: 3},
    ?key: ?value,
  };
  values[1] = 4;
  return values.length * 10 + values[1]! + (values[2] ?? 0);
}

int loopControl() {
  var result = 0;
  for (final v in <int>[1, 2, 3, 4]) {
    if (v == 2) continue;
    if (v == 4) break;
    result += v;
  }
  return result;
}

int capturedLoop() {
  var first = () => 0;
  var second = () => 0;
  for (var v in <int>[1, 2]) {
    if (v == 1) {
      first = () => v;
    } else {
      second = () => v;
    }
    v += 10;
  }
  return first() * 100 + second();
}

int existingLoop() {
  var v = 0;
  final read = () => v;
  for (v in <int>[1, 2, 3]) {}
  return read();
}

int patternLoop() {
  var result = 0;
  for (final (a, b) in <(int, int)>[(1, 2), (3, 4)]) {
    result += a * b;
  }
  return result;
}

int nestedCollection() => sum(<int>[
  for (final v in <int>[1, 2, 3])
    if (v > 1) ...<int>[v, v * 10],
]);
int mutation() {
  final values = <int>[1, 2];
  for (final v in values) {
    values.add(v);
  }
  return 0;
}

int mapNullOrder() {
  var n = 0;
  int? key() {
    n += 1;
    return null;
  }

  int value() {
    n += 10;
    return 1;
  }

  final m = <int, int>{?key(): value()};
  return n + m.length;
}

int aliasCheck() {
  List<num> values = <int>[1];
  values.add(1.5);
  return values.length;
}

int countedCollection() => sum(<int>[for (var i = 0; i < 4; i++) i * 2]);
int patternConditional() => sum(<int>[
  if ((1, 2) case (final int a, final int b) when a < b) a + b else 9,
]);
int listUpdates() {
  final values = <int>[1, 2];
  values[0] += 3;
  final old = values[1]++;
  return values[0] * 100 + old * 10 + values[1];
}

class Cursor() implements Iterator<int> {
  int index = 0;
  int reads = 0;
  @override
  int get current {
    reads += 1;
    return index;
  }

  @override
  bool moveNext() {
    index += 1;
    return index <= 3;
  }
}

class Sequence() implements Iterable<int> {
  int requests = 0;
  final Cursor cursor = Cursor();
  @override
  Iterator<int> get iterator {
    requests += 1;
    return cursor;
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int customIteration() {
  final sequence = Sequence();
  var sum = 0;
  for (final v in sequence) {
    sum += v;
  }
  return sum * 100 + sequence.requests * 10 + sequence.cursor.reads;
}

class Pairs() implements Map<int, int> {
  int visits = 0;
  @override
  void forEach(void Function(int, int) action) {
    visits += 1;
    action(1, 7);
    action(2, 8);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int customMapSpread() {
  final pairs = Pairs();
  final map = <int, int>{...pairs};
  return pairs.visits * 100 + map[1]! * 10 + map[2]!;
}

int loopFinally() {
  var n = 0;
  for (final v in <int>[1, 2, 3]) {
    try {
      if (v == 1) continue;
      break;
    } finally {
      n += v;
    }
  }
  return n;
}

int aliasSpreadCheck() {
  List<num> values = <int>[];
  values.addAll(<num>[1.5]);
  return values.length;
}

class Key(final int id) {
  @override
  int get hashCode => id;
  @override
  bool operator ==(Object other) => other is Key && id == other.id;
}

int equalityKeys() {
  final map = <Key, int>{Key(1): 2, Key(1): 3};
  final set = <Key>{Key(2), Key(2)};
  return map.length * 100 + map[Key(1)]! * 10 + set.length;
}

class Bucket<T>() {
  List<T> make(T value) => <T>[value];
}

bool genericCollection() {
  Object value = Bucket<int>().make(3);
  return value is List<int>;
}

int countedCollectionClosures() {
  final callbacks = <int Function()>[for (var i = 0; i < 3; i++) () => i];
  return callbacks[0]() * 100 + callbacks[1]() * 10 + callbacks[2]();
}

int forInCollectionClosures() {
  final callbacks = <int Function()>[
    for (var i in <int>[1, 2, 3]) () => ++i,
  ];
  final first = callbacks[0]() * 100 + callbacks[1]() * 10 + callbacks[2]();
  return first * 1000 +
      callbacks[0]() * 100 +
      callbacks[1]() * 10 +
      callbacks[2]();
}

int existingCollectionClosures() {
  var i = 0;
  final callbacks = <int Function()>[
    for (i in <int>[1, 2, 3]) () => i,
  ];
  i = 4;
  return callbacks[0]() * 100 + callbacks[1]() * 10 + callbacks[2]();
}

class IterationTrace(final int failure) {
  int trace = 0;
  void record(int event) {
    trace = trace * 10 + event;
  }
}

class TracedCursor(final IterationTrace state) implements Iterator<int> {
  int index = 0;
  @override
  bool moveNext() {
    state.record(3);
    index++;
    if (state.failure == 2 && index == 2) throw 22;
    return index <= 2;
  }

  @override
  int get current {
    state.record(4);
    if (state.failure == 3 && index == 2) throw 33;
    return index;
  }
}

class TracedSequence(final IterationTrace state) implements Iterable<int> {
  @override
  Iterator<int> get iterator {
    state.record(2);
    if (state.failure == 1) throw 11;
    return TracedCursor(state);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int collectionExceptionOrder(int failure) {
  final state = IterationTrace(failure);
  Iterable<int> source() {
    state.record(1);
    return TracedSequence(state);
  }

  int body(int value) {
    state.record(5);
    if (failure == 4 && value == 2) throw 44;
    return value;
  }

  try {
    final values = <int>[for (final value in source()) body(value)];
    state.record(6);
    if (values.length != 2) throw 99;
  } catch (_) {
    state.record(7);
  } finally {
    state.record(8);
  }
  return state.trace;
}

int spreadExceptionOrder(int failure) {
  final state = IterationTrace(failure);
  Iterable<int> source() {
    state.record(1);
    return TracedSequence(state);
  }

  int tail() {
    state.record(6);
    return 9;
  }

  try {
    final values = <int>[...source(), tail()];
    if (values.length != 3) throw 99;
  } catch (_) {
    state.record(7);
  } finally {
    state.record(8);
  }
  return state.trace;
}
