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
  invocation,
  dispatchFailure,
  exhaustivenessFailure,
  floatingRemainder,
  floatingModulo,
  captureStackTrace,
  recordError,
  asyncCreate,
  asyncStart,
  asyncAwait,
  asyncReturn,
  typeSubtype,
  typeEquals,
  typeHash,
  typeArgumentsEqual,
  typeArgumentsHash,
  typeNullable,
  typeFutureOr,
  typeParameter,
  typeShift,
  typeAt,
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
  className,
  typeView,
  typeSupertypes,
  captureStackTrace,
  uncheckedCast,
  instantiateClosure,
}

/// Excludes this reference slot from strong tracing.
final class const WeakSlot();

/// Pairs a nullable key slot with a nullable value slot in the same class.
final class const EphemeronKey(final String valueField);

/// Identifies an immutable map and its interleaved key/value list field.
final class const ConstantMapStorage(final String data);

/// Identifies the immutable set implementation and its constant map field.
final class const ConstantSetStorage(final String entries);

/// Identifies List storage for constant materialization and literal spreading.
final class const ConstantListStorage(
  final String length,
  final String data,
  final String spread,
);

/// Marks variable payload words as managed references.
final class const ReferencePayload();

/// Binds record instances to a class with an inline, traced field payload.
final class const RecordStorage();

/// Reified type shapes shared with native metadata.
enum TypeKind() {
  nominal,
  nullable,
  futureOr,
  function,
  record,
  parameter,
  dynamicType,
  voidType,
  never,
  nullType,
}

/// Binds a Dart class to its compiler-generated type metadata.
final class const TypeStorage(final int kind);
