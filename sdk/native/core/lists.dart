import 'dart:_heap/objects.dart'
    show lengthOf, loadReference, newArray, storeReference;

RangeError _outside(int index, int length) =>
    RangeError.range(index, 0, length - 1, 'length');

@patch
class _Array<E> {
  @patch
  E operator [](int index) {
    if (index < 0 || index >= lengthOf(this)) {
      throw _outside(index, lengthOf(this));
    }
    return unsafeCast<E>(loadReference(this, index));
  }

  @patch
  int get length => lengthOf(this);

  @patch
  _List _sliceInternal(int start, int count, bool needsTypeArgument) {
    final result = needsTypeArgument ? _List<E>(count) : _List(count);
    for (var i = 0; i < count; i++) {
      storeReference(result, i, loadReference(this, start + i));
    }
    return result;
  }

  void _set(int index, Object? value) {
    if (index < 0 || index >= lengthOf(this)) {
      throw RangeError.range(index, 0, lengthOf(this) - 1, 'index');
    }
    storeReference(this, index, value);
  }
}

@patch
@pragma('dartc:elements', 'references')
class _List<E> {
  static const _maxLength = 576460752303423487;

  @patch
  factory _List(length) {
    final int count = length;
    if (count < 0 || count > _maxLength) {
      throw RangeError.range(count, 0, _maxLength, 'length');
    }
    return newArray<_List<E>>(count);
  }

  @patch
  void _setIndexed(int index, E value) => _set(index, value);
}

@patch
@pragma('dartc:elements', 'references')
class _ImmutableList<E> {
  @patch
  factory _ImmutableList._from(List from, int offset, int length) {
    final result = newArray<_ImmutableList<E>>(length);
    for (var i = 0; i < length; i++) {
      storeReference(result, i, from[offset + i]);
    }
    return result;
  }
}

@patch
class _GrowableList<T> {
  _List _data;
  int _length = 0;

  _GrowableList._of(this._data);

  @patch
  factory _GrowableList._withData(_List data) => _GrowableList<T>._of(data);

  @patch
  int get _capacity => lengthOf(_data);

  @patch
  int get length => _length;

  @patch
  void _setLength(int new_length) {
    _length = new_length;
  }

  @patch
  void _setData(_List array) {
    _data = array;
  }

  @patch
  T operator [](int index) {
    if (index < 0 || index >= _length) throw _outside(index, _length);
    return unsafeCast<T>(loadReference(_data, index));
  }

  @patch
  void _setIndexed(int index, Object? value) {
    if (index < 0 || index >= _length) {
      throw RangeError.range(index, 0, _length - 1, 'index');
    }
    storeReference(_data, index, value);
  }

  static final _List _noElements = _List(0);

  @patch
  static _List get _emptyList => _noElements;
}

/// A list with the elements of [data], which it uses itself.
List<T> _listOf<T>(_List data) {
  if (data.length == 0) return _GrowableList<T>(0);
  return _GrowableList<T>._withData(data).._setLength(data.length);
}

/// Adds [value], which is of the right type.
void _addElement(_GrowableList list, Object? value) {
  final length = list.length;
  if (length == list._capacity) list._growToNextCapacity();
  list._setLength(length + 1);
  list._setIndexed(length, value);
}

Map<K, V> _newMap<K, V>() => LinkedHashMap<K, V>();
Set<E> _newSet<E>() => LinkedHashSet<E>();

void _addToMap(Map map, Object? key, Object? value) {
  map[key] = value;
}

void _addToSet(Set set, Object? value) {
  set.add(value);
}

Iterable<MapEntry> _entriesOf(Map map) => map.entries;
Object? _keyOf(MapEntry entry) => entry.key;
Object? _valueOf(MapEntry entry) => entry.value;
