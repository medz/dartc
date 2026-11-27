import 'dart:_internal' show patch;

@patch
abstract class _LinkedHashBase {
  Uint32List? _ownIndex;

  @patch
  Uint32List get _index => _ownIndex!;
  @patch
  void set _index(Uint32List value) {
    _ownIndex = value;
  }

  @patch
  int _hashMask = 0;
  @patch
  List _data = _uninitializedData;
  @patch
  int _usedData = 0;
  @patch
  int _deletedKeys = 0;
}

/// The indexes of constant maps and sets, which never change themselves.
final List<Uint32List?> _indexes = [];

@patch
abstract class _LinkedHashImmutableBase {
  // The slot for a compiled constant. Maps built at run time keep -1.
  int _place = -1;

  @patch
  List get _data => super._data;

  @patch
  Uint32List? get _indexNullable {
    if (_place < 0) return _ownIndex;
    return _place < _indexes.length ? _indexes[_place] : null;
  }

  @patch
  void set _index(Uint32List value) {
    if (_place < 0) {
      super._index = value;
      return;
    }
    while (_indexes.length <= _place) {
      _indexes.add(null);
    }
    _indexes[_place] = value;
  }
}

@patch
mixin _OperatorEqualsAndCanonicalHashCode {
  @patch
  static int get cidSymbol => -1;

  // Keys of constant maps that have another are equal only to themselves.
  @patch
  int _hashCode(Object? e) => e.hashCode;
}

final Uint32List _noIndex = Uint32List(_HashBase._UNINITIALIZED_INDEX_SIZE);
final List _noData = List.filled(0, null);

@patch
Uint32List get _uninitializedIndex => _noIndex;

@patch
List get _uninitializedData => _noData;

@patch
final class _ConstMap<K, V> {
  /// Has the keys and values of [map].
  _ConstMap._of(Map<K, V> map) {
    final data = List<Object?>.filled(map.length * 2, null);
    var at = 0;
    map.forEach((key, value) {
      data[at++] = key;
      data[at++] = value;
    });
    // As the maps do it when they make their index.
    final size = at <= 8 ? 8 : 1 << (at - 1).bitLength;
    _data = data;
    _usedData = at;
    _hashMask = (1 << (32 - (size.bitLength - 2))) - 1;
    // The first lookup builds the index.
    _ownIndex = null;
  }
}

@patch
_ConstMap<K, V> createConstMapFromMapOfDeeplyImmutables<K, V>(Map<K, V> map) =>
    _ConstMap._of(map);
