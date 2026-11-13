import 'dart:_internal' show ListData, NativeList;

@patch
class List<E> {
  // A literal here would call this factory again during native construction.
  @patch
  @pragma(
    'dartc:patch',
    'storage: list literals delegate to this factory on the target',
  )
  factory List.empty({bool growable}) =>
      growable ? _GrowableList<E>.empty() : _List<E>(0);
}

@patch
abstract class _Array<E>._storage(
  final int _storageLength,
  final ListData _storageData,
) implements NativeList<E> {
  @patch
  int get length => _storageLength;

  @patch
  E operator [](int index) {
    _checkStorageIndex(index);
    return _storageData[index] as E;
  }

  void _checkStorageIndex(int index) {
    if (index < 0 || index >= length) {
      throw IndexError.withLength(
        index,
        length,
        indexable: this,
        name: 'index',
      );
    }
  }

  @patch
  _List _sliceInternal(int start, int count, bool needsTypeArgument) =>
      needsTypeArgument
      ? _List<E>.generate(count, (i) => this[start + i])
      : _List<dynamic>.generate(count, (i) => this[start + i]);

  @override
  NativeList<E> toFixedLength() => this;

  @override
  NativeList<E> toUnmodifiable() =>
      NativeList<E>.unmodifiable(length, _storageData);
}

@patch
class _List<E> {
  _List._storage(int length, ListData data) : super._storage(length, data);

  @patch
  factory _List(length) => _List<E>._storage(
    RangeError.checkNotNegative(length as int, 'length'),
    ListData.create(length),
  );

  @patch
  void _setIndexed(int index, E value) {
    _checkStorageIndex(index);
    _storageData[index] = value;
  }

  @patch
  @pragma(
    'dartc:patch',
    'specification: List.setRange rejects negative skips and insufficient input',
  )
  void setRange(int start, int end, Iterable<E> iterable, [int skipCount]) =>
      // The generic SDK path rejects negative skips and insufficient input.
      super.setRange(start, end, iterable, skipCount);
}

@patch
class _GrowableList<T>._storage(var _List _storageData)
    implements NativeList<T> {
  int _storageLength = 0;
  static final _List _emptyStorage = _List(0);

  @patch
  factory _GrowableList._withData(_List data) => ._storage(data);

  @patch
  int get _capacity => _storageData.length;
  @patch
  int get length => _storageLength;
  @patch
  void _setLength(int new_length) => _storageLength =
      RangeError.checkValueInInterval(new_length, 0, _capacity, 'length');
  @patch
  void _setData(_List array) => _storageData = array;
  @patch
  static _List get _emptyList => _emptyStorage;

  void _checkStorageIndex(int index) {
    if (index < 0 || index >= length) {
      throw IndexError.withLength(
        index,
        length,
        indexable: this,
        name: 'index',
      );
    }
  }

  @patch
  T operator [](int index) {
    _checkStorageIndex(index);
    return _storageData[index] as T;
  }

  @patch
  void _setIndexed(int index, Object? value) {
    _checkStorageIndex(index);
    _storageData[index] = value;
  }

  @override
  NativeList<T> toFixedLength() =>
      _List<T>._storage(length, _storageData._storageData);

  @override
  NativeList<T> toUnmodifiable() =>
      NativeList<T>.unmodifiable(length, _storageData._storageData);
}
