import 'dart:_internal' show checkValidWeakTarget;
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
  @patch
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
    checkValidWeakTarget(value, 'value');
    if (detach != null) checkValidWeakTarget(detach, 'detach');
    super.attach(value, finalizationToken, detach: detach);
  }
}

@patch
class Object {
  external int get _identityHashCode;
}

@patch
class _WeakReference<T extends Object> {
  @runtime.WeakSlot()
  T? _storage;

  @patch
  T? get target => _storage;
  @patch
  set _target(T? value) => _storage = value;
}

@patch
class _WeakProperty {
  @runtime.EphemeronKey('_value')
  dynamic _key;
  dynamic _value;

  @patch
  get key => _key;
  @patch
  set key(k) => _key = k;
  @patch
  get value => _value;
  @patch
  set value(v) => _value = v;
}
