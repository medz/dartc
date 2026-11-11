/// Rejects allocation, throwing and foreign reentry throughout a call closure.
final class const NonAllocating();

/// Identifies a compiler entry without depending on its Dart name.
final class const RuntimeEntry(final RuntimeRole role);

enum RuntimeRole() {
  allocate,
  release,
  runEvents,
  events,
}

/// Binds an external declaration to one trusted machine operation.
final class const Primitive(final MemoryOperation operation);

enum MemoryOperation() {
  map,
  unmap,
  read,
  write,
  addressOf,
  objectAt,
  fail,
  context,
  writeByte,
  writeBytes,
  clock,
  sleep,
}

/// Excludes this reference slot from strong tracing.
final class const WeakSlot();

/// Pairs a nullable key slot with a nullable value slot in the same class.
final class const EphemeronKey(final String valueField);

/// Identifies the immutable map implementation and its parallel constant lists.
final class const ConstantMapStorage(final String keys, final String values);
