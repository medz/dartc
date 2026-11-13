import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart' as runtime;
import '../runtime/memory.dart';

/// Traced reference storage shared by mutable and constant lists.
@runtime.ReferencePayload()
final class ListData {
  @runtime.Primitive(.allocatePayload)
  external static ListData _allocate(int bytes);

  static ListData create(int length) {
    const maximum = (0x1ffffffffffffff8 - ObjectHeader.fieldsOffset) ~/ 8;
    return _allocate(length > maximum ? -1 : length * 8);
  }

  Object? operator [](int index) =>
      Memory.readReference(this, ObjectHeader.fieldsOffset + index * 8);

  void operator []=(int index, Object? value) =>
      Memory.writeReference(this, ObjectHeader.fieldsOffset + index * 8, value);
}

/// Storage conversions shared by the core list implementations.
abstract interface class NativeList<E> implements List<E> {
  factory NativeList.unmodifiable(int length, ListData data) = _ConstantList<E>;
  NativeList<E> toFixedLength();
  NativeList<E> toUnmodifiable();
}

@runtime.ConstantListStorage('_length', '_data', 'spread')
final class _ConstantList<E>(final int _length, final ListData _data)
    extends UnmodifiableListBase<E>
    implements NativeList<E> {
  @override
  NativeList<E> toFixedLength() => this;

  @override
  NativeList<E> toUnmodifiable() => this;

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
