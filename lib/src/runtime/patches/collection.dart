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
