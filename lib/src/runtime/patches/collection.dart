import '../contracts.dart' as runtime;

@runtime.ConstantSetStorage('_map')
@patch
class _UnmodifiableSet<E> {}

@patch
class LinkedHashMap<K, V> {
  @patch
  factory LinkedHashMap({
    bool Function(K, K)? equals,
    int Function(K)? hashCode,
    bool Function(dynamic)? isValidKey,
  }) => _OrderedMap<K, V>(
    HashMap<K, _OrderedEntry<K, V>>(
      equals: equals,
      hashCode: hashCode,
      isValidKey: isValidKey,
    ),
  );

  @patch
  factory LinkedHashMap.identity() =>
      _OrderedMap<K, V>(HashMap<K, _OrderedEntry<K, V>>.identity());
}

final class _OrderedMap<K, V>(final HashMap<K, _OrderedEntry<K, V>> _entries)
    extends MapBase<K, V>
    implements LinkedHashMap<K, V> {
  final _order = LinkedList<_OrderedEntry<K, V>>();

  @override
  int get length => _entries.length;

  @override
  Iterable<K> get keys => _order.map((entry) => entry.key);

  @override
  bool containsKey(Object? key) => _entries.containsKey(key);

  @override
  V? operator [](Object? key) => _entries[key]?.value;

  @override
  void operator []=(K key, V value) {
    final previous = _entries[key];
    if (previous != null) {
      previous.value = value;
      return;
    }
    final entry = _OrderedEntry(key, value);
    _entries[key] = entry;
    _order.add(entry);
  }

  @override
  V? remove(Object? key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    entry.unlink();
    return entry.value;
  }

  @override
  void clear() {
    _entries.clear();
    _order.clear();
  }
}

final class _OrderedEntry<K, V>(final K key, V initialValue)
    extends LinkedListEntry<_OrderedEntry<K, V>> {
  V value = initialValue;
}

@patch
class LinkedHashSet<E> {
  @patch
  factory LinkedHashSet({
    bool Function(E, E)? equals,
    int Function(E)? hashCode,
    bool Function(dynamic)? isValidKey,
  }) => _OrderedSet<E>(equals, hashCode, isValidKey);

  @patch
  factory LinkedHashSet.identity() =>
      _OrderedSet<E>(identical, identityHashCode, null);
}

final class _OrderedSet<E>(
  final bool Function(E, E)? _equals,
  final int Function(E)? _hashCode,
  final bool Function(dynamic)? _isValidKey,
) extends SetBase<E> implements LinkedHashSet<E> {
  final _entries = LinkedHashMap<E, E>(
    equals: _equals,
    hashCode: _hashCode,
    isValidKey: _isValidKey,
  );

  @override
  int get length => _entries.length;
  @override
  Iterator<E> get iterator => _entries.keys.iterator;
  @override
  bool contains(Object? value) => _entries.containsKey(value);
  @override
  E? lookup(Object? value) => _entries[value];
  @override
  bool add(E value) {
    if (_entries.containsKey(value)) return false;
    _entries[value] = value;
    return true;
  }

  @override
  bool remove(Object? value) {
    if (!_entries.containsKey(value)) return false;
    _entries.remove(value);
    return true;
  }

  @override
  void clear() => _entries.clear();
  @override
  Set<E> toSet() =>
      _OrderedSet<E>(_equals, _hashCode, _isValidKey)..addAll(this);
}
