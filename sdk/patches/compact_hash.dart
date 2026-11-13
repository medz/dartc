import 'dart:typed_data' show Uint32List;

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
