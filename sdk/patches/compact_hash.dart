import 'dart:typed_data' show Uint32List;

import '../../lib/runtime/contracts.dart' as runtime;

final _emptyIndex = Uint32List(1);
final _emptyData = List<dynamic>.empty();

@patch
Uint32List get _uninitializedIndex => _emptyIndex;

@patch
List get _uninitializedData => _emptyData;

@patch
class _LinkedHashBase {
  late Uint32List _indexStorage;
  late List _dataStorage;
  int _maskStorage = 0;
  int _usedStorage = 0;
  int _deletedStorage = 0;

  @patch
  Uint32List get _index => _indexStorage;
  @patch
  set _index(Uint32List value) => _indexStorage = value;

  @patch
  int get _hashMask => _maskStorage;
  @patch
  set _hashMask(int value) => _maskStorage = value;

  @patch
  List get _data => _dataStorage;
  @patch
  set _data(List value) => _dataStorage = value;

  @patch
  int get _usedData => _usedStorage;
  @patch
  set _usedData(int value) => _usedStorage = value;

  @patch
  int get _deletedKeys => _deletedStorage;
  @patch
  set _deletedKeys(int value) => _deletedStorage = value;
}

@runtime.ConstantMapStorage('_constantData')
@patch
class _ConstMap<K, V> {}

// Constant objects are read-only; the SDK's lazy index uses existing weak storage.
abstract class _LinkedHashImmutableBase._storage(final List _constantData)
    implements _LinkedHashBase {
  static final _indexes = Expando<Uint32List>();

  Uint32List get _indexStorage => _index;
  set _indexStorage(Uint32List value) => _index = value;
  List get _dataStorage => _data;
  set _dataStorage(List value) => _data = value;
  int get _maskStorage => _hashMask;
  set _maskStorage(int value) => _hashMask = value;
  int get _usedStorage => _usedData;
  set _usedStorage(int value) => _usedData = value;
  int get _deletedStorage => _deletedKeys;
  set _deletedStorage(int value) => _deletedKeys = value;

  Uint32List? get _indexNullable => _indexes[this];
  Uint32List get _index => _indexNullable!;
  set _index(Uint32List value) => _indexes[this] = value;
  List get _data => _constantData;
  int get _usedData => _data.length;
  int get _deletedKeys => 0;
  int get _hashMask => _HashBase._indexSizeToHashMask(
    _roundUpToPowerOfTwo(max(_data.length, _HashBase._INITIAL_INDEX_SIZE)),
  );

  set _data(List value) => throw UnsupportedError('Unmodifiable hash data');
  set _usedData(int value) => throw UnsupportedError('Unmodifiable hash data');
  set _deletedKeys(int value) =>
      throw UnsupportedError('Unmodifiable hash data');
  set _hashMask(int value) => throw UnsupportedError('Unmodifiable hash data');
}

@patch
mixin _OperatorEqualsAndCanonicalHashCode {
  @patch
  @pragma(
    'dartc:patch',
    'storage: target class IDs have no VM predefined-class interval',
  )
  int _hashCode(Object? e) =>
      e is num || e is String || e is Symbol || e is Type
      ? e.hashCode
      : identityHashCode(e);
}
