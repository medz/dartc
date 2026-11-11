import 'dart:ffi' as ffi;

import '../contracts.dart' as runtime;

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
