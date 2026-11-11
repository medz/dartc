@patch
class HashMap<K, V> {
  factory HashMap({
    bool Function(K, K)? equals,
    int Function(K)? hashCode,
    bool Function(dynamic)? isValidKey,
  }) => _HashMap<K, V>(equals, hashCode, isValidKey);

  factory HashMap.identity() =>
      _HashMap<K, V>(identical, identityHashCode, null);
}

final class _HashMap<K, V>(
  final bool Function(K, K)? _equals,
  final int Function(K)? _hash,
  final bool Function(dynamic)? _valid,
) extends MapBase<K, V> implements HashMap<K, V> {
  final _data = <_HashKey<K, V>, V>{};

  bool _accepts(Object? key) => _valid != null
      ? _valid(key)
      : (_equals == null && _hash == null || key is K);

  @override
  V? operator [](Object? key) =>
      _accepts(key) ? _data[_HashKey(this, key)] : null;
  @override
  bool containsKey(Object? key) =>
      _accepts(key) && _data.containsKey(_HashKey(this, key));
  @override
  void operator []=(K key, V value) => _data[_HashKey(this, key)] = value;
  @override
  V? remove(Object? key) =>
      _accepts(key) ? _data.remove(_HashKey(this, key)) : null;
  @override
  void clear() => _data.clear();
  @override
  int get length => _data.length;
  @override
  Iterable<K> get keys => _HashKeys<K, V>(_data);
}

final class _HashKey<K, V>(final _HashMap<K, V> owner, final Object? value) {
  @override
  int get hashCode =>
      owner._hash == null ? value.hashCode : owner._hash!(value as K);
  @override
  bool operator ==(Object other) =>
      other is _HashKey<K, V> &&
      (owner._equals == null
          ? value == other.value
          : owner._equals!(value as K, other.value as K));
}

final class _HashKeys<K, V>(final Map<_HashKey<K, V>, V> data)
    extends Iterable<K> {
  @override
  Iterator<K> get iterator => _HashIterator<K, V>(data.keys.iterator);
  @override
  int get length => data.length;
}

final class _HashIterator<K, V>(final Iterator<_HashKey<K, V>> delegate)
    implements Iterator<K> {
  @override
  K get current => delegate.current.value as K;
  @override
  bool moveNext() => delegate.moveNext();
}
