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
/// The header contains a storage descriptor, a traced runtime type and a stable
/// identity hash and allocated size. Fields keep their representation across generic
/// instantiations.
final class ObjectLayout(
  Iterable<ValueRepresentation> fields, {

  /// Whether every aligned slot after the fixed fields is a managed reference.
  final bool tracesPayload = false,
}) {
  /// Immutable representations in physical field order.
  final List<ValueRepresentation> fields = .unmodifiable(fields);

  /// The alignment and width of every object slot.
  static const int alignment = 8;

  /// The byte offset of the immutable storage descriptor address.
  static const int descriptorOffset = 0;

  /// The byte offset of the managed runtime type reference.
  static const int typeOffset = alignment;

  /// The byte offset of the identity hash retained when the object moves.
  static const int identityHashOffset = 2 * alignment;

  /// The aligned allocation size, including any trailing inline payload.
  static const int sizeOffset = 3 * alignment;

  /// The byte offset of the first instance field or boxed scalar payload.
  static const int fieldsOffset = 4 * alignment;

  /// The fixed storage size, including the header but excluding inline payloads.
  int get size => fieldsOffset + fields.length * alignment;

  /// The byte offset of [field] in this object's storage.
  int offsetOf(int field) {
    RangeError.checkValidIndex(field, fields, 'field');
    return fieldsOffset + field * alignment;
  }

  /// The runtime type and fields traced by the collector, excluding other headers.
  Iterable<int> get referenceOffsets sync* {
    yield typeOffset;
    for (final (i, representation) in fields.indexed) {
      if (representation == .reference) yield offsetOf(i);
    }
  }
}
