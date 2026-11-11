import 'memory_layout.dart';

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
  Iterable<int> weakFields = const [],
  Map<int, int> ephemerons = const {},
}) {
  /// Immutable representations in physical field order.
  final List<ValueRepresentation> fields = .unmodifiable(fields);

  /// Field indices that do not retain their references.
  final Set<int> weakFields = .unmodifiable(weakFields);

  /// Conditional key/value field indices.
  final Map<int, int> ephemerons = .unmodifiable(ephemerons);

  this {
    final conditional = {...this.ephemerons.keys, ...this.ephemerons.values};
    if (conditional.length != this.ephemerons.length * 2 ||
        conditional.any(this.weakFields.contains)) {
      throw ArgumentError('Repeated conditional reference slot.');
    }
    for (final index in {...this.weakFields, ...conditional}) {
      RangeError.checkValidIndex(index, this.fields);
      if (this.fields[index] != .reference) {
        throw ArgumentError('Weak storage requires a reference.');
      }
    }
  }

  /// The fixed storage size, including the header but excluding inline payloads.
  int get size =>
      ObjectHeader.fieldsOffset + fields.length * ObjectHeader.alignment;

  /// The byte offset of [field] in this object's storage.
  int offsetOf(int field) {
    RangeError.checkValidIndex(field, fields, 'field');
    return ObjectHeader.fieldsOffset + field * ObjectHeader.alignment;
  }

  /// The runtime type and fields traced by the collector, excluding other headers.
  Iterable<int> get referenceOffsets sync* {
    yield ObjectHeader.typeOffset;
    for (final (i, representation) in fields.indexed) {
      if (representation == .reference &&
          !weakFields.contains(i) &&
          !ephemerons.containsKey(i) &&
          !ephemerons.containsValue(i)) {
        yield offsetOf(i);
      }
    }
  }
}
