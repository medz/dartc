/// Byte offsets in a managed object's header on 64-bit targets.
abstract final class ObjectHeader() {
  /// The alignment and width of every object slot.
  static const alignment = 8;

  /// The immutable storage descriptor address.
  static const descriptorOffset = 0;

  /// The traced runtime type reference.
  static const typeOffset = alignment;

  /// The stable identity hash of the object.
  static const identityHashOffset = 2 * alignment;

  /// The aligned allocation size, including inline payload.
  static const sizeOffset = 3 * alignment;

  /// The owning heap page, or zero for control and constant storage.
  static const pageOffset = 4 * alignment;

  /// The first instance field or boxed scalar payload.
  static const fieldsOffset = 5 * alignment;
}

/// Word indices in a storage descriptor shared by allocation and collection.
abstract final class ObjectDescriptor() {
  /// The fixed allocation size, excluding inline payload.
  static const size = 0;

  /// The number of traced reference fields.
  static const referenceCount = 1;

  /// The first traced field's byte offset.
  static const references = 2;

  /// Add the reference count to locate the exception trace field offset.
  static const traceBase = references;

  /// Add the reference count to locate the traced payload offset.
  static const payloadBase = references + 1;

  /// Add the strong reference count to locate optional closure metadata.
  static const asyncBase = references + 2;

  /// Add the strong reference count to locate the weak slot count.
  static const weakCountBase = references + 3;

  /// Add the strong reference count to locate the conditional pair count.
  static const ephemeronCountBase = references + 4;

  /// Strong offsets precede weak offsets and then key/value offset pairs.
  static const baseWords = references + 5;
}

/// Machine entry records shared by native boundaries and the Dart runtime.
abstract final class RuntimeContext() {
  static const heap = 0;
  static const bootstrap = 8;
  static const initializing = 16;
  static const maps = 24;
  static const globalRoots = 32;
  static const active = 40;
  static const controlCursor = 48;
  static const controlLimit = 56;
  static const size = 64;
  static const previousEntry = 0;
  static const suspendedSp = 8;
  static const suspendedPc = 16;
  static const entrySize = 24;
}

/// A sorted return-PC index followed by shared, variable-length root records.
abstract final class StackMapTable() {
  static const count = 0;
  static const entries = 8;
  static const entrySize = 16;
  static const pc = 0;

  /// The record's byte offset from the start of the table.
  static const record = 8;
}

/// Byte offsets in a root record addressed by the stack-map index.
abstract final class StackMapRecord() {
  /// The constant frame-description address, or zero for an unnamed frame.
  static const description = 0;

  /// One plus the stack offset of the traced continuation, or zero.
  static const context = 8;
  static const callerStack = 16;
  static const returnAddress = 24;
  static const rootCount = 32;
  static const roots = 40;
}

/// Byte offsets in optional immutable function-value metadata.
abstract final class ClosureTraceMetadata() {
  static const description = 0;
  static const link = 8;
  static const value = 16;
  static const bound = 24;
  static const size = 32;
}
