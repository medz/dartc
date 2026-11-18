import 'signature.dart';
import 'type.dart';

/// An invariant logical view of one managed allocation's physical slots.
///
/// The allocation producer establishes this contract. A compatible Dart class
/// type, cast or layout does not establish it. Slot types describe values; the
/// physical declaration continues to own offsets and execution carriers.
final class StorageView(
  final ClassType storageType,
  final ValueType capability,
  Map<InstanceField, ValueType> fields,
) {
  final Map<InstanceField, ValueType> fields = .unmodifiable(fields);

  this {
    if (storageType.isAbstract ||
        fields.entries.any((entry) =>
            storageType.asInstanceOf(entry.key.owner) == null ||
            !isDartType(entry.value))) {
      throw ArgumentError('Invalid invariant storage view.');
    }
  }

  ValueType typeOf(InstanceField field) => fields[field] ??
      (throw ArgumentError('The field is not part of this storage view.'));

  Iterable<TypeParameterType> get freeTypeParameters => {
    ...storageType.freeTypeParameters,
    ...capability.freeTypeParameters,
    for (final type in fields.values) ...type.freeTypeParameters,
  };

  StorageView mapTypes(ValueType Function(ValueType) map) {
    final physical = map(storageType) as ClassType;
    final logical = map(capability);
    final mapped = {for (final entry in fields.entries) entry.key: map(entry.value)};
    if (physical == storageType && logical == capability &&
        mapped.entries.every((entry) => fields[entry.key] == entry.value)) {
      return this;
    }
    return StorageView(physical, logical, mapped);
  }

  @override
  bool operator ==(Object other) => other is StorageView &&
      other.storageType == storageType && other.capability == capability &&
      other.fields.length == fields.length &&
      fields.entries.every((entry) => other.fields[entry.key] == entry.value);

  @override
  int get hashCode => Object.hash(storageType, capability,
      Object.hashAllUnordered(fields.entries.map((entry) => (entry.key, entry.value))));
}
