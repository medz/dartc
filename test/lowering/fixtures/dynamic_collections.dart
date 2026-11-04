import 'effects.dart';

class DynamicCursor(final bool bad) implements Iterator<Object?> {
  int index = 0;
  @override
  bool moveNext() {
    tick(20 + index);
    index += 1;
    return index <= 3;
  }

  @override
  Object? get current {
    tick(30 + index);
    return bad && index == 2 ? 'bad' : index;
  }
}

class DynamicSequence(final bool bad) implements Iterable<Object?> {
  @override
  Iterator<Object?> get iterator {
    tick(10);
    return DynamicCursor(bad);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

class Duck() {
  Iterator<Object?> get iterator {
    tick(90);
    return DynamicCursor(false);
  }
}

int dynamicLoop(bool bad) {
  dynamic source = DynamicSequence(bad);
  var sum = 0;
  for (final int value in source) {
    sum += tick(40 + value);
  }
  return sum;
}

int dynamicCollectionLoop(bool bad) {
  dynamic source = DynamicSequence(bad);
  return <int>[for (final int value in source) tick(40 + value)].length;
}

int dynamicSequenceSpread(bool bad, bool set) {
  dynamic source = DynamicSequence(bad);
  if (set) return <int>{...source, tick(50)}.length;
  return <int>[...source, tick(50)].length;
}

int dynamicDuck(int mode) {
  dynamic source = Duck();
  if (mode == 0) {
    for (final int value in source) {
      tick(value);
    }
    return 0;
  }
  if (mode == 1) return <int>[...source].length;
  if (mode == 2) return <int>{...source}.length;
  return <int, int>{...source}.length;
}

int dynamicNull(int mode, bool aware) {
  dynamic source;
  if (mode == 0) {
    for (final int value in source) {
      tick(value);
    }
    return 0;
  }
  if (mode == 1) {
    return aware ? <int>[...?source, tick(50)].length : <int>[...source].length;
  }
  if (mode == 2) {
    return aware ? <int>{...?source, tick(50)}.length : <int>{...source}.length;
  }
  return aware
      ? <int, int>{...?source, tick(50): 1}.length
      : <int, int>{...source}.length;
}

class DynamicPairs(final bool bad) implements Map<dynamic, dynamic> {
  @override
  Iterable<MapEntry<dynamic, dynamic>> get entries {
    tick(60);
    return [MapEntry(1, 2), MapEntry(3, bad ? 'bad' : 4), MapEntry(5, 6)];
  }

  @override
  void forEach(void Function(dynamic, dynamic) action) {
    tick(70);
    action(1, 2);
    tick(71);
    action(3, bad ? 'bad' : 4);
    tick(72);
    action(5, 6);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int dynamicMapSpread(bool bad, int target) {
  dynamic source = DynamicPairs(bad);
  if (target == 0) return <int, int>{...source, tick(80): 9}.length;
  if (target == 1) return <Object?, Object?>{...source, tick(80): 9}.length;
  if (target == 2) return <dynamic, dynamic>{...source, tick(80): 9}.length;
  if (target == 3) return <int, Object?>{...source, tick(80): 9}.length;
  return <Object?, int>{...source, tick(80): 9}.length;
}

int staticDynamicMapSpread(bool bad, bool checked) {
  Map<dynamic, dynamic> source = DynamicPairs(bad);
  if (checked) return <int, int>{...source, tick(80): 9}.length;
  return <dynamic, dynamic>{...source, tick(80): 9}.length;
}

int staticObjectMapSpread(bool bad) {
  Map<Object?, Object?> source = DynamicPairs(bad);
  return <Object?, Object?>{...source, tick(80): 9}.length;
}

int genericMapSpread<K, V>(Map<K, V> source) {
  return <K, V>{...source}.length;
}

int genericMapCase() => genericMapSpread<int, int>({1: 2});

int entryValues() {
  const first = MapEntry<int, int>(2, 3);
  final second = MapEntry<int, int>(tick(4), tick(5));
  return first.key * 1000 + first.value * 100 + second.key * 10 + second.value;
}

int broadDynamicValues() {
  dynamic sequence = <Object?>[1];
  dynamic map = <Object?, Object?>{1: 2};
  var result = 0;
  for (final int value in sequence) {
    result += value;
  }
  return result +
      <int>[...sequence].length +
      <int>{...sequence}.length +
      <int, int>{...map}.length;
}

class EntryCursor(final int failure)
    implements Iterator<MapEntry<dynamic, dynamic>> {
  int index = 0;
  @override
  bool moveNext() {
    tick(100 + index);
    index += 1;
    return index <= 3;
  }

  @override
  MapEntry<dynamic, dynamic> get current {
    tick(110 + index);
    return MapEntry(
      index == 2 && failure == 1 ? 'bad' : index,
      index == 2 && failure == 2 ? 'bad' : index + 1,
    );
  }
}

class EntrySequence(final int failure)
    implements Iterable<MapEntry<dynamic, dynamic>> {
  @override
  Iterator<MapEntry<dynamic, dynamic>> get iterator {
    tick(90);
    return EntryCursor(failure);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

class OrderedPairs(final int failure) implements Map<dynamic, dynamic> {
  @override
  Iterable<MapEntry<dynamic, dynamic>> get entries {
    tick(80);
    return EntrySequence(failure);
  }

  @override
  Never noSuchMethod(Object invocation) => throw 99;
}

int mapEntryOrder(int failure) {
  dynamic source = OrderedPairs(failure);
  return <int, int>{...source, tick(120): 1}.length;
}

int genericCheckedMap<K>(Map<K, dynamic> source) => <K, int>{...source}.length;

int genericCheckedMapCase(bool bad) {
  return genericCheckedMap<dynamic>(DynamicPairs(bad));
}

int dynamicNullAwareValues(bool bad, bool map) {
  dynamic source = map ? DynamicPairs(bad) : DynamicSequence(bad);
  if (map) return <int, int>{...?source, tick(80): 9}.length;
  return <int>[...?source, tick(50)].length;
}

int mapEntriesLiveView() {
  final map = <int, int>{1: 2};
  final Iterable<MapEntry<int, int>> entries = map.entries;
  map[3] = 4;
  var sum = 0;
  for (final entry in entries) {
    sum += tick(entry.key) * 10 + tick(entry.value);
  }
  return sum;
}

int customMapEntries() {
  Map<dynamic, dynamic> map = OrderedPairs(0);
  final entries = map.entries;
  tick(85);
  var sum = 0;
  for (final entry in entries) {
    final int key = entry.key;
    final int value = entry.value;
    sum += key * 10 + value;
  }
  return sum;
}

int genericEntries<K, V>(Map<K, V> source) {
  final Iterable<MapEntry<K, V>> entries = source.entries;
  return [for (final entry in entries) (entry.key, entry.value)].length;
}

int genericEntriesCase() => genericEntries<int, String>({1: 'one'});
