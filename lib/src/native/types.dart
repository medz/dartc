/// A type of C on a system with addresses of 64 bits.
sealed class const NativeType() {
  /// The bytes that a value takes, and what its address is a multiple of.
  int get size;
  int get alignment;
}

final class const NativeVoid() extends NativeType {
  @override
  int get size => 0;
  @override
  int get alignment => 1;
}

final class const NativeInteger(
  @override final int size, {
  required final bool isSigned,
}) extends NativeType {
  @override
  int get alignment => size;
}

final class const NativeBoolean() extends NativeType {
  @override
  int get size => 1;
  @override
  int get alignment => 1;
}

final class const NativeFloating(@override final int size) extends NativeType {
  @override
  int get alignment => size;
}

final class const NativePointer() extends NativeType {
  @override
  int get size => 8;
  @override
  int get alignment => 8;
}

final class const NativeArray(final NativeType element, final int count)
    extends NativeType {
  @override
  int get size => element.size * count;
  @override
  int get alignment => element.alignment;
}

/// A struct or union. Its fields are supplied once by [define], so that they
/// can refer to it through pointers.
final class NativeCompound(
  final String name, {
  final bool isUnion = false,

  /// The largest alignment that fields have, if there is a limit.
  final int? packing,
}) extends NativeType {
  List<NativeType>? _fields;
  late final List<int> _offsets;

  void define(Iterable<NativeType> fields) {
    if (_fields != null) throw StateError('$name already has fields.');
    _fields = .unmodifiable(fields);
    var end = 0;
    _offsets = [
      for (final field in this.fields)
        if (isUnion) 0 else (end = _endOf(field, end)) - field.size,
    ];
  }

  List<NativeType> get fields =>
      _fields ?? (throw StateError('$name has no fields.'));

  /// Where each field is.
  List<int> get offsets {
    fields;
    return _offsets;
  }

  int _alignmentOf(NativeType field) => switch (packing) {
    final limit? when limit < field.alignment => limit,
    _ => field.alignment,
  };

  /// Where [field] ends if those before it end at [end].
  int _endOf(NativeType field, int end) =>
      alignTo(end, _alignmentOf(field)) + field.size;

  @override
  int get alignment =>
      fields.map(_alignmentOf).fold(1, (a, b) => a > b ? a : b);

  @override
  int get size {
    var end = 0;
    for (final field in fields) {
      final own = isUnion ? field.size : _endOf(field, end);
      if (own > end) end = own;
    }
    return alignTo(end, alignment);
  }
}

/// The least multiple of [alignment] that is not less than [value].
int alignTo(int value, int alignment) =>
    (value + alignment - 1) ~/ alignment * alignment;

/// The parameters and result of a C function.
///
/// The parameters from [fixedCount] on, if that is given, are variable.
final class NativeSignature(
  Iterable<NativeType> parameters,
  final NativeType result, {
  final int? fixedCount,
}) {
  final List<NativeType> parameters = .unmodifiable(parameters);

  bool isVariable(int index) => switch (fixedCount) {
    null => false,
    final count => index >= count,
  };
}
