/// Immutable sparse storage with shared hash-trie versions.
///
/// Updates copy one hash path. Merging versions skips identical subtrees and
/// visits absent entries through [merge]'s callback, which can supply defaults.
final class StateMap<K extends Object, V extends Object> {
  final _Node<K, V>? _root;

  const new empty() : _root = null;
  const new _(this._root);

  factory fromEntries(Iterable<MapEntry<K, V>> entries) {
    var result = StateMap<K, V>.empty();
    for (final entry in entries) {
      result = result.withEntry(entry.key, entry.value);
    }
    return result;
  }

  V? operator [](K key) {
    var node = _root;
    final hash = key.hashCode & 0x3fffffff;
    var shift = 0;
    while (node is _Branch<K, V>) {
      node = (hash >> shift++) & 1 == 0 ? node.left : node.right;
    }
    if (node is! _Leaf<K, V> || node.hash != hash) return null;
    for (final entry in node.items) {
      if (entry.key == key) return entry.value;
    }
    return null;
  }

  bool get isEmpty => _root == null;

  Iterable<MapEntry<K, V>> get entries => _entries(_root);
  Iterable<K> get keys => entries.map((entry) => entry.key);
  Iterable<V> get values => entries.map((entry) => entry.value);

  StateMap<K, V> withEntry(K key, V value) {
    final next = _put(_root, key.hashCode & 0x3fffffff, key, value, 0);
    return identical(next, _root) ? this : StateMap._(next);
  }

  StateMap<K, V> withoutKey(K key) {
    final next = _remove(_root, key.hashCode & 0x3fffffff, key, 0);
    return identical(next, _root) ? this : StateMap._(next);
  }

  /// Only differing entries; shared subtrees are never enumerated.
  Iterable<({K key, V? before, V? after})> differences(StateMap<K, V> before) =>
      _differences(before._root, _root, 0);

  @override
  int get hashCode => _root?.contentHash ?? 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateMap<K, V> &&
          (_root?.size ?? 0) == (other._root?.size ?? 0) &&
          hashCode == other.hashCode &&
          differences(other).isEmpty;

  StateMap<K, V> mapValues(V Function(K, V) transform) {
    final next = _map(_root, transform);
    return identical(next, _root) ? this : StateMap._(next);
  }

  /// Joins entries with an idempotent [combine], including missing overrides.
  StateMap<K, V> merge(StateMap<K, V> other, V? Function(K, V?, V?) combine) {
    final next = _merge(_root, other._root, 0, combine);
    if (identical(next, _root)) return this;
    return identical(next, other._root) ? other : StateMap._(next);
  }
}

sealed class const _Node<K extends Object, V extends Object>() {
  int get contentHash;
  int get size;
}

final class _Leaf<K extends Object, V extends Object>(
  final int hash,
  Iterable<MapEntry<K, V>> items,
) extends _Node<K, V> {
  final List<MapEntry<K, V>> items = .unmodifiable(items);
  @override
  late final int contentHash = items.fold(
    0,
    (hash, entry) => (hash + Object.hash(entry.key, entry.value)) & 0x3fffffff,
  );
  @override
  int get size => items.length;
}

final class _Branch<K extends Object, V extends Object>(
  final _Node<K, V>? left,
  final _Node<K, V>? right,
) extends _Node<K, V> {
  @override
  late final int contentHash =
      ((left?.contentHash ?? 0) + (right?.contentHash ?? 0)) & 0x3fffffff;
  @override
  late final int size = (left?.size ?? 0) + (right?.size ?? 0);
}

Iterable<MapEntry<K, V>> _entries<K extends Object, V extends Object>(
  _Node<K, V>? node,
) sync* {
  if (node is _Leaf<K, V>) {
    yield* node.items;
  } else if (node is _Branch<K, V>) {
    yield* _entries(node.left);
    yield* _entries(node.right);
  }
}

_Node<K, V> _put<K extends Object, V extends Object>(
  _Node<K, V>? node,
  int hash,
  K key,
  V value,
  int shift,
) {
  if (node == null) return _Leaf(hash, [MapEntry(key, value)]);
  if (node is _Leaf<K, V>) {
    if (node.hash != hash) {
      if ((node.hash >> shift) & 1 == (hash >> shift) & 1) {
        final child = _put(node, hash, key, value, shift + 1);
        return (hash >> shift) & 1 == 0
            ? _Branch(child, null)
            : _Branch(null, child);
      }
      final fresh = _Leaf(hash, [MapEntry(key, value)]);
      return (hash >> shift) & 1 == 0
          ? _Branch(fresh, node)
          : _Branch(node, fresh);
    }
    final index = node.items.indexWhere((entry) => entry.key == key);
    if (index >= 0 && node.items[index].value == value) return node;
    final items = [...node.items];
    if (index < 0) {
      items.add(MapEntry(key, value));
    } else {
      items[index] = MapEntry(key, value);
    }
    return _Leaf(hash, items);
  }
  final branch = node as _Branch<K, V>;
  if ((hash >> shift) & 1 == 0) {
    final child = _put(branch.left, hash, key, value, shift + 1);
    return identical(child, branch.left) ? node : _Branch(child, branch.right);
  }
  final child = _put(branch.right, hash, key, value, shift + 1);
  return identical(child, branch.right) ? node : _Branch(branch.left, child);
}

_Node<K, V>? _merge<K extends Object, V extends Object>(
  _Node<K, V>? a,
  _Node<K, V>? b,
  int shift,
  V? Function(K, V?, V?) combine,
) {
  if (identical(a, b)) return a;
  if (a == null) return _map(b, (key, value) => combine(key, null, value));
  if (b == null) return _map(a, (key, value) => combine(key, value, null));
  if (a is _Leaf<K, V> && b is _Leaf<K, V> && a.hash == b.hash) {
    final keys = <K>{
      for (final entry in a.items) entry.key,
      for (final entry in b.items) entry.key,
    };
    V? get(_Leaf<K, V> node, K key) {
      for (final entry in node.items) {
        if (entry.key == key) return entry.value;
      }
      return null;
    }

    _Node<K, V>? result = a;
    for (final key in keys) {
      final value = combine(key, get(a, key), get(b, key));
      result = value == null
          ? _remove(result, key.hashCode & 0x3fffffff, key, shift)
          : _put(result, key.hashCode & 0x3fffffff, key, value, shift);
    }
    return result;
  }
  (_Node<K, V>?, _Node<K, V>?) children(_Node<K, V> node) =>
      node is _Branch<K, V>
      ? (node.left, node.right)
      : ((node as _Leaf<K, V>).hash >> shift) & 1 == 0
      ? (node, null)
      : (null, node);
  final left = children(a), right = children(b);
  final joinedLeft = _merge(left.$1, right.$1, shift + 1, combine);
  final joinedRight = _merge(left.$2, right.$2, shift + 1, combine);
  if (a is _Branch<K, V> &&
      identical(joinedLeft, a.left) &&
      identical(joinedRight, a.right)) {
    return a;
  }
  if (b is _Branch<K, V> &&
      identical(joinedLeft, b.left) &&
      identical(joinedRight, b.right)) {
    return b;
  }
  return _trim(joinedLeft, joinedRight);
}

_Node<K, V>? _map<K extends Object, V extends Object>(
  _Node<K, V>? node,
  V? Function(K, V) transform,
) {
  if (node == null) return null;
  if (node is _Leaf<K, V>) {
    var changed = false;
    final items = <MapEntry<K, V>>[];
    for (final entry in node.items) {
      final value = transform(entry.key, entry.value);
      changed |= value != entry.value;
      if (value != null) items.add(MapEntry(entry.key, value));
    }
    return !changed
        ? node
        : items.isEmpty
        ? null
        : _Leaf(node.hash, items);
  }
  final branch = node as _Branch<K, V>;
  final left = _map(branch.left, transform),
      right = _map(branch.right, transform);
  return identical(left, branch.left) && identical(right, branch.right)
      ? node
      : _trim(left, right);
}

_Node<K, V>? _trim<K extends Object, V extends Object>(
  _Node<K, V>? left,
  _Node<K, V>? right,
) {
  if (left == null && (right == null || right is _Leaf<K, V>)) return right;
  if (right == null && left is _Leaf<K, V>) return left;
  return _Branch(left, right);
}

_Node<K, V>? _remove<K extends Object, V extends Object>(
  _Node<K, V>? node,
  int hash,
  K key,
  int shift,
) {
  if (node == null) return null;
  if (node is _Leaf<K, V>) {
    if (node.hash != hash || !node.items.any((entry) => entry.key == key)) {
      return node;
    }
    final items = node.items.where((entry) => entry.key != key).toList();
    return items.isEmpty ? null : _Leaf(node.hash, items);
  }
  final branch = node as _Branch<K, V>;
  if ((hash >> shift) & 1 == 0) {
    final left = _remove(branch.left, hash, key, shift + 1);
    return identical(left, branch.left) ? node : _trim(left, branch.right);
  }
  final right = _remove(branch.right, hash, key, shift + 1);
  return identical(right, branch.right) ? node : _trim(branch.left, right);
}

Iterable<({K key, V? before, V? after})> _differences<
  K extends Object,
  V extends Object
>(_Node<K, V>? before, _Node<K, V>? after, int shift) sync* {
  if (identical(before, after)) return;
  if (before == null) {
    for (final entry in _entries(after)) {
      yield (key: entry.key, before: null, after: entry.value);
    }
    return;
  }
  if (after == null) {
    for (final entry in _entries(before)) {
      yield (key: entry.key, before: entry.value, after: null);
    }
    return;
  }
  if (before is _Leaf<K, V> && after is _Leaf<K, V>) {
    final keys = {
      ...before.items.map((e) => e.key),
      ...after.items.map((e) => e.key),
    };
    for (final key in keys) {
      final a = before.items.where((e) => e.key == key).firstOrNull?.value;
      final b = after.items.where((e) => e.key == key).firstOrNull?.value;
      if (a != b) yield (key: key, before: a, after: b);
    }
    return;
  }
  (_Node<K, V>?, _Node<K, V>?) children(_Node<K, V> node) =>
      node is _Branch<K, V>
      ? (node.left, node.right)
      : ((node as _Leaf<K, V>).hash >> shift) & 1 == 0
      ? (node, null)
      : (null, node);
  final a = children(before), b = children(after);
  yield* _differences(a.$1, b.$1, shift + 1);
  yield* _differences(a.$2, b.$2, shift + 1);
}
