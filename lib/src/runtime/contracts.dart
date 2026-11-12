/// Rejects allocation, throwing and foreign reentry throughout a call closure.
final class const NonAllocating();

/// Identifies a compiler entry without depending on its Dart name.
final class const RuntimeEntry(final RuntimeRole role);

enum RuntimeRole() {
  allocate,
  release,
  runEvents,
  events,
  copyBytes,
}

/// Binds an external declaration to one trusted machine operation.
final class const Primitive(final MemoryOperation operation);

enum MemoryOperation() {
  map,
  unmap,
  read,
  readByte,
  write,
  addressOf,
  objectAt,
  fail,
  context,
  writeByte,
  writeBytes,
  clock,
  sleep,
  allocatePayload,
  readReference,
  writeReference,
  keepAlive,
  float32FromBits,
  float64FromBits,
  float32Bits,
  float64Bits,
}

/// Excludes this reference slot from strong tracing.
final class const WeakSlot();

/// Pairs a nullable key slot with a nullable value slot in the same class.
final class const EphemeronKey(final String valueField);

/// Identifies the immutable map implementation and its parallel constant lists.
final class const ConstantMapStorage(final String keys, final String values);

/// Identifies List storage for constant materialization and literal spreading.
final class const ConstantListStorage(
  final String length,
  final String data,
  final String mutability,
  final String spread,
);

/// Marks variable payload words as managed references.
final class const ReferencePayload();
