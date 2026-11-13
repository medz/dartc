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

  /// Add the strong reference count to locate the weak slot count.
  static const weakCountBase = references + 2;

  /// Add the strong reference count to locate the conditional pair count.
  static const ephemeronCountBase = references + 3;

  /// Strong offsets precede weak offsets and then key/value offset pairs.
  static const baseWords = references + 4;
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

/// Byte offsets in stack-map records, following the table's entry count.
abstract final class StackMapRecord() {
  static const tableHeader = 8;
  static const pc = 0;
  static const callerStack = 8;
  static const returnAddress = 16;
  static const rootCount = 24;
  static const roots = 32;
}
