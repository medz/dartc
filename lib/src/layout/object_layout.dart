/// The interpretation of one 64-bit value slot.
enum ValueRepresentation() {
  /// An unboxed integer or boolean.
  word,

  /// An IEEE 754 binary64 value.
  floating,

  /// A native pointer that is not traced as a managed reference.
  address,

  /// A managed object address, or zero for Dart null.
  reference,
}

/// An object header followed by its fields, including inherited storage.
///
/// The header contains the address of the concrete type's descriptor. Fields
/// keep their declaration's representation across generic instantiations.
final class ObjectLayout(Iterable<ValueRepresentation> fields) {
  /// Immutable representations in physical field order.
  final List<ValueRepresentation> fields = .unmodifiable(fields);

  /// The alignment and width of every object slot.
  static const int alignment = 8;

  /// The byte offset of the type descriptor address.
  static const int typeOffset = 0;

  /// The total storage size, including the header of an empty object.
  int get size => (fields.length + 1) * alignment;

  /// The byte offset of [field] in this object's storage.
  int offsetOf(int field) {
    RangeError.checkValidIndex(field, fields, 'field');
    return (field + 1) * alignment;
  }

  /// The fields containing managed references; the immutable type header is excluded.
  Iterable<int> get referenceOffsets sync* {
    for (final (i, representation) in fields.indexed) {
      if (representation == .reference) yield offsetOf(i);
    }
  }
}
