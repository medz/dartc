import '../memory.dart';

@patch
class Array<T extends NativeType> {
  final Object _nativeOwner;
  final List<int> _shape;
  final int _elementBytes;

  Array._view(Object owner, int address, this._shape, this._elementBytes)
    : _nativeOwner = owner,
      super._fromTypedDataBase(Pointer<Void>.fromAddress(address), 0);

  int _addressAt(int index) {
    final length = _shape.first;
    if (index < 0 || index >= length) {
      throw IndexError.withLength(
        index,
        length,
        indexable: this,
        name: 'index',
      );
    }
    return (_typedDataBase as Pointer<Void>).address + index * _elementBytes;
  }
}

@patch
class _ArraySize<T extends NativeType> {
  Object get _nativeOwner => throw UnsupportedError('Array annotation');
  List<int> get _shape => throw UnsupportedError('Array annotation');
  int get _elementBytes => throw UnsupportedError('Array annotation');
  int _addressAt(int index) => throw UnsupportedError('Array annotation');
}

Array<T> _arraySlice<T extends NativeType>(Array<Array<T>> array, int index) {
  final address = array._addressAt(index);
  final shape = array._shape.sublist(1);
  return Array<T>._view(
    array,
    address,
    shape,
    array._elementBytes ~/ shape.first,
  );
}

void _copyArray(Array<NativeType> target, Array<NativeType> source) {
  Memory.copyBytes(
    (target._typedDataBase as Pointer<Void>).address,
    (source._typedDataBase as Pointer<Void>).address,
    target._shape.first * target._elementBytes,
  );
  Memory.keepAlive(target);
  Memory.keepAlive(source);
}

int _arrayAddress(Array<NativeType> value, int index) =>
    value._addressAt(index);

void _arrayStore<T extends NativeType>(
  Array<Array<T>> target,
  int index,
  Array<T> value,
) => _copyArray(_arraySlice(target, index), value);
