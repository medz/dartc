import 'dart:collection' show ListBase;
import 'dart:_internal' show FixedLengthListMixin, UnmodifiableListBase;

import '../../../layout/memory.dart';

import '../contracts.dart' as runtime;
import '../memory.dart';

@patch
class List<E> {
  @patch
  factory List.empty({bool growable}) => _NativeList<E>.empty(growable);

  @patch
  factory List.filled(int length, E fill, {bool growable}) =>
      _NativeList<E>.filled(length, fill, growable);

  @patch
  factory List.from(Iterable<Object?> elements, {bool growable}) =>
      _NativeList<E>.from(elements, growable);

  @patch
  factory List.of(Iterable<E> elements, {bool growable}) =>
      _NativeList<E>.from(elements, growable);

  @patch
  factory List.generate(
    int length,
    E Function(int) generator, {
    bool growable,
  }) {
    RangeError.checkNotNegative(length);
    final result = _NativeList<E>.empty(true);
    for (var i = 0; i < length; i++) {
      result.add(generator(i));
    }
    return growable ? result : _FixedList<E>(result._length, result._data);
  }

  @patch
  factory List.unmodifiable(Iterable elements) {
    final copy = _NativeList<E>.from(elements, true);
    return _ConstantList<E>(copy._length, copy._data);
  }
}

@runtime.ReferencePayload()
final class _ListData {
  @runtime.Primitive(.allocatePayload)
  external static _ListData _allocate(int bytes);

  static _ListData create(int length) {
    const maximum = (0x1ffffffffffffff8 - ObjectHeader.fieldsOffset) ~/ 8;
    return _allocate(length > maximum ? -1 : length * 8);
  }

  int get capacity =>
      (Memory.read(Memory.addressOf(this) + ObjectHeader.sizeOffset) -
          ObjectHeader.fieldsOffset) ~/
      8;

  Object? operator [](int index) =>
      Memory.readReference(this, ObjectHeader.fieldsOffset + index * 8);

  void operator []=(int index, Object? value) =>
      Memory.writeReference(this, ObjectHeader.fieldsOffset + index * 8, value);
}

base class _NativeList<E>(int length, _ListData data) extends ListBase<E> {
  int _length = length;
  _ListData _data = data;

  factory empty(bool growable) => growable
      ? .new(0, _ListData.create(0))
      : _FixedList<E>(0, _ListData.create(0));

  factory filled(int length, E fill, bool growable) {
    RangeError.checkNotNegative(length);
    final data = _ListData.create(length);
    for (var i = 0; i < length; i++) {
      data[i] = fill;
    }
    return growable ? .new(length, data) : _FixedList<E>(length, data);
  }

  factory from(Iterable<Object?> elements, bool growable) {
    final result = _NativeList<E>.empty(true);
    for (final element in elements) {
      result.add(element as E);
    }
    return growable ? result : _FixedList<E>(result._length, result._data);
  }

  @override
  int get length => _length;

  @override
  set length(int value) {
    RangeError.checkNotNegative(value);
    if (value > _length) {
      null as E;
      _reserve(value);
    } else {
      for (var i = value; i < _length; i++) {
        _data[i] = null;
      }
    }
    _length = value;
  }

  @override
  E operator [](int index) {
    _checkIndex(index);
    return _data[index] as E;
  }

  @override
  void operator []=(int index, E value) {
    _checkIndex(index);
    _data[index] = value;
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= _length) {
      throw IndexError.withLength(
        index,
        _length,
        indexable: this,
        name: 'index',
      );
    }
  }

  void _reserve(int required) {
    final capacity = _data.capacity;
    if (required <= capacity) return;
    final grown = capacity * 2 + 4;
    final data = _ListData.create(required > grown ? required : grown);
    for (var i = 0; i < _length; i++) {
      data[i] = _data[i];
    }
    _data = data;
  }

  @override
  void add(E value) {
    _reserve(_length + 1);
    _data[_length++] = value;
  }

  @override
  void addAll(Iterable<E> values) {
    if (identical(values, this)) {
      if (isEmpty) return;
      throw ConcurrentModificationError(this);
    }
    var expected = _length;
    for (final value in values) {
      if (_length != expected) throw ConcurrentModificationError(this);
      add(value);
      expected++;
    }
  }
}

final class _FixedList<E>(int length, _ListData data)
    extends _NativeList<E>
    with FixedLengthListMixin<E> {
  this : super(length, data);
}

@runtime.ConstantListStorage('_length', '_data', 'spread')
final class _ConstantList<E>(final int _length, final _ListData _data)
    extends UnmodifiableListBase<E> {
  @override
  int get length => _length;

  @override
  E operator [](int index) {
    if (index < 0 || index >= _length) {
      throw IndexError.withLength(
        index,
        _length,
        indexable: this,
        name: 'index',
      );
    }
    return _data[index] as E;
  }

  static void spread<T>(List<T> target, Iterable<Object?> source) {
    for (final value in source) {
      target.add(value as T);
    }
  }
}
