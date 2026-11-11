import 'dart:ffi' as ffi;
import 'dart:async' as async;
import 'dart:collection' as collection;

import '../contracts.dart' as runtime;
import '../allocator.dart' as allocator;
import '../finalization.dart' as finalization;

@runtime.ConstantMapStorage('_keys', '_values')
final class const _ConstantMap<K, V>(final List<K> _keys, final List<V> _values)
    extends collection.MapBase<K, V> {
  int _index(Object? key) {
    for (var i = 0; i < _keys.length; i++) {
      if (_keys[i] == key) return i;
    }
    return -1;
  }

  @override
  V? operator [](Object? key) {
    final index = _index(key);
    return index < 0 ? null : _values[index];
  }

  @override
  bool containsKey(Object? key) => _index(key) >= 0;
  @override
  int get length => _keys.length;
  @override
  Iterable<K> get keys => _keys;
  @override
  void operator []=(K key, V value) => throw UnsupportedError('Immutable map');
  @override
  V? remove(Object? key) => throw UnsupportedError('Immutable map');
  @override
  void clear() => throw UnsupportedError('Immutable map');
}

@patch
class Finalizer<T> {
  factory Finalizer(void Function(T) callback) => _Finalizer<T>(callback);
}

final class _Finalizer<T>(void Function(T) callback)
    extends finalization.FinalizerHandle<T>
    implements Finalizer<T> {
  this
    : super(
        allocator.events().finalizers,
        async.Zone.current.bindUnaryCallbackGuarded(callback),
      );

  @override
  void attach(Object value, T finalizationToken, {Object? detach}) {
    _checkWeakTarget(value, 'value');
    if (detach != null) _checkWeakTarget(detach, 'detach');
    super.attach(value, finalizationToken, detach: detach);
  }
}

@patch
class WeakReference<T extends Object> {
  factory WeakReference(T target) => _WeakReference<T>(target);
}

final class _WeakReference<T extends Object>(T value)
    implements WeakReference<T> {
  @runtime.WeakSlot()
  T? _target = value;

  @override
  T? get target => _target;

  this {
    _checkWeakTarget(value, 'target');
  }
}

void _checkWeakTarget(Object value, String parameter) {
  if (value is num ||
      value is String ||
      value is bool ||
      value is Record ||
      value is ffi.Pointer ||
      value is ffi.Struct ||
      value is ffi.Union) {
    throw ArgumentError.value(
      value,
      parameter,
      'Invalid weak reference target',
    );
  }
}

@patch
class Expando<T extends Object> {
  new([String? name]) : name = name;

  var _buckets = <int, _ExpandoEntry<T>>{};
  int _count = 0, _sweepAt = 32;

  T? operator [](Object object) {
    _checkWeakTarget(object, 'object');
    for (
      var entry = _buckets[identityHashCode(object)];
      entry != null;
      entry = entry.next
    ) {
      if (identical(entry.key, object)) return entry.value;
    }
    return null;
  }

  void operator []=(Object object, T? value) {
    _checkWeakTarget(object, 'object');
    final hash = identityHashCode(object);
    for (var entry = _buckets[hash]; entry != null; entry = entry.next) {
      if (identical(entry.key, object)) {
        entry.value = value;
        if (value == null) entry.key = null;
        return;
      }
    }
    if (value == null) return;
    if (_count >= _sweepAt) _compact();
    _buckets[hash] = _ExpandoEntry(object, value, _buckets[hash]);
    _count++;
  }

  void _compact() {
    final buckets = <int, _ExpandoEntry<T>>{};
    var count = 0;
    for (final bucket in _buckets.entries) {
      for (
        _ExpandoEntry<T>? entry = bucket.value;
        entry != null;
        entry = entry.next
      ) {
        final key = entry.key, value = entry.value;
        if (key != null && value != null) {
          buckets[bucket.key] = _ExpandoEntry(key, value, buckets[bucket.key]);
          count++;
        }
      }
    }
    _buckets = buckets;
    _count = count;
    _sweepAt = count * 2 + 32;
  }
}

final class _ExpandoEntry<T extends Object>(
  Object key,
  T value,
  final _ExpandoEntry<T>? next,
) {
  @runtime.EphemeronKey('value')
  Object? key = key;
  T? value = value;
}
