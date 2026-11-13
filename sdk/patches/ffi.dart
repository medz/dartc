import 'dart:_internal' show checkValidWeakTarget;

import '../../lib/runtime/contracts.dart' as runtime;

import '../runtime/memory.dart';
import '../runtime/type_info.dart';
import '../runtime/allocator.dart' as allocator;
import '../runtime/finalization.dart' as finalization;
import '../runtime/native_callbacks.dart' as callbacks;

@patch
@runtime.Primitive(.abi)
external int _abi();

NativeCallable<T> _newNativeCallable<T extends Function>(
  Function callback,
  int entry,
) {
  final address = callbacks.register(entry, callback);
  try {
    final result = _NativeCallableIsolateLocal<T>(Pointer.fromAddress(address));
    allocator.events().keepCallbackAlive(1);
    return result;
  } catch (_) {
    callbacks.unregister(address);
    rethrow;
  }
}

Function _nativeCallableTarget(int address) => callbacks.target(address);

@patch
void _deleteNativeCallable<NS extends NativeFunction>(Pointer<NS> pointer) =>
    callbacks.unregister(pointer.address);

@patch
void _updateNativeCallableKeepIsolateAliveCounter<NS extends NativeFunction>(
  int delta,
) => allocator.events().keepCallbackAlive(delta);

@patch
class NativeFinalizer {
  @patch
  factory NativeFinalizer(Pointer<NativeFinalizerFunction> callback) =>
      _NativeFinalizer(callback);
}

final class _NativeFinalizer(
  @override final Pointer<NativeFinalizerFunction> callback,
) extends finalization.FinalizerHandle<Pointer<Void>>
    implements NativeFinalizer {
  this
    : super(
        allocator.events().finalizers,
        callback.asFunction<void Function(Pointer<Void>)>(isLeaf: true),
        isNative: true,
      ) {
    if (callback.address == 0) throw ArgumentError.value(callback, 'callback');
  }

  @override
  void attach(
    covariant Finalizable value,
    Pointer<Void> token, {
    Object? detach,
    int? externalSize,
  }) {
    if (detach != null) checkValidWeakTarget(detach, 'detach');
    queue.attach(
      this,
      value,
      token,
      detachKey: detach,
      externalSize: externalSize ?? 0,
    );
  }
}

void _attachPointerFinalizer(
  Pointer<NativeFinalizerFunction>? callback,
  Finalizable owner,
  Pointer pointer,
  Pointer<Void>? token,
  int byteLength,
) {
  if (callback == null) return;
  NativeFinalizer(callback)
      .attach(owner, token ?? pointer.cast<Void>(), externalSize: byteLength);
}

@patch
class Array<T extends NativeType> {
  final Object _nativeOwner;
  final List<int> _shape;
  final int _elementBytes;
  final bool _variableLength;

  Array._view(
    Object owner,
    int address,
    this._shape,
    this._elementBytes,
    this._variableLength,
  ) : _nativeOwner = owner,
      super._fromTypedDataBase(Pointer<Void>.fromAddress(address), 0);

  int get _size => _shape.first;

  void _checkIndex(int index) {
    if (_variableLength) return;
    if (index < 0 || index >= _size) {
      throw IndexError.withLength(index, _size, indexable: this, name: 'index');
    }
  }

  int _addressAt(int index) {
    _checkIndex(index);
    return _arrayElementAddress(this, index);
  }
}

int _arrayElementAddress(Array<NativeType> array, int index) =>
    _arrayStart(array) + index * array._elementBytes;

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
    false,
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

int _arrayStart(Array<NativeType> value) =>
    (value._typedDataBase as Pointer<Void>).address;

int _arrayLength(Array<NativeType> value) => value._size;

Array<T> _fixedArray<T extends NativeType>(Array<T> array) =>
    array._variableLength
    ? Array<T>._view(
        array,
        _arrayStart(array),
        array._shape,
        array._elementBytes,
        false,
      )
    : array;

void _arrayStore<T extends NativeType>(
  Array<Array<T>> target,
  int index,
  Array<T> value,
) => _copyArray(_arraySlice(target, index), value);

// Nested views retain an owner and byte stride instead of VM typed-data storage.
final class _NestedArrayList<T extends NativeType>(final Array<Array<T>> _array)
    with ListMixin<Array<T>>, FixedLengthListMixin<Array<T>> {
  @override
  int get length => _array._size;

  @override
  Array<T> operator [](int index) => _arraySlice(_array, index);

  @override
  void operator []=(int index, Array<T> value) =>
      _arrayStore(_array, index, value);
}

void _checkAsFunctionType(Type requested, Type representation) {
  final actual = TypeInfo.of(requested), expected = TypeInfo.of(representation);
  final shape = actual.signature;
  var valid =
      actual.kind == expected.kind &&
      !actual.allowsNull &&
      shape != null &&
      shape.binders == 0 &&
      shape.named == null &&
      shape.required == shape.positional &&
      shape.positional == expected.signature!.positional;
  if (valid) {
    final pointer = TypeInfo.of(Pointer);
    var result = true;
    for (var a = actual.parts, b = expected.parts; b != null; b = b.tail) {
      if (a == null) {
        valid = false;
        break;
      }
      final source = a.head, target = b.head;
      valid = target.kind == pointer.kind && target.shape == pointer.shape
          ? source.kind == pointer.kind &&
                source.shape == pointer.shape &&
                (result
                    ? target.isSubtypeOf(source)
                    : source.isSubtypeOf(target))
          : source == target;
      if (!valid) break;
      a = a.tail;
      result = false;
    }
  }
  if (!valid) {
    throw ArgumentError.value(
      requested,
      'DF',
      'Incompatible native function representation',
    );
  }
}
