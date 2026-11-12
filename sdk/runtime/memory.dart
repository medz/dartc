import '../../lib/runtime/contracts.dart';

/// Zero-filled managed byte storage, with no traced payload slots.
final class ByteStorage() {
  @Primitive(.allocatePayload)
  external static ByteStorage allocate(int length);
}

/// Trusted machine capabilities; callers own bounds, alignment and lifetimes.
abstract final class Memory() {
  @Primitive(.float32FromBits)
  external static double float32FromBits(int bits);
  @Primitive(.float64FromBits)
  external static double float64FromBits(int bits);
  @Primitive(.float32Bits)
  external static int float32Bits(double value);
  @Primitive(.float64Bits)
  external static int float64Bits(double value);

  /// Keeps [value] reachable until this point, including through native calls.
  @Primitive(.keepAlive)
  external static void keepAlive(Object? value);

  /// Reads a managed slot; [offset] is a byte offset including the object header.
  @Primitive(.readReference)
  external static Object? readReference(Object object, int offset);

  /// Writes a managed slot without losing its owner across a collection.
  @Primitive(.writeReference)
  external static void writeReference(Object object, int offset, Object? value);

  /// The active Dart execution context, preserved across native reentry.
  @Primitive(.context)
  external static int context();

  @Primitive(.writeByte)
  external static void writeByte(int address, int value);

  @Primitive(.readByte)
  external static int readByte(int address);

  /// Copies live byte storage, preserving overlapping ranges.
  @RuntimeEntry(.copyBytes)
  @NonAllocating()
  static void copyBytes(int destination, int source, int count) {
    if (destination <= source || destination - source >= count) {
      for (var i = 0; i < count; i++) {
        writeByte(destination + i, readByte(source + i));
      }
    } else {
      for (var i = count - 1; i >= 0; i--) {
        writeByte(destination + i, readByte(source + i));
      }
    }
  }

  @Primitive(.writeBytes)
  external static int writeBytes(int descriptor, int address, int count);

  /// Monotonic nanoseconds since an unspecified origin.
  @Primitive(.clock)
  external static int clock();

  /// Waits for a relative timeout, or returns early on a signal.
  @Primitive(.sleep)
  external static void sleep(int seconds, int nanoseconds);

  /// Reserves zero-filled pages, or returns zero on exhaustion.
  @Primitive(.map)
  external static int map(int bytes);

  /// Releases a region returned by [map].
  @Primitive(.unmap)
  external static void unmap(int address, int bytes);

  /// Reads one aligned machine word from live storage.
  @Primitive(.read)
  external static int read(int address);

  /// Writes one aligned machine word to live storage.
  @Primitive(.write)
  external static void write(int address, int value);

  /// Observes an object's address while moving collection is suspended.
  @Primitive(.addressOf)
  external static int addressOf(Object? value);

  /// Recovers an existing object whose initialized storage has type [T].
  @Primitive(.objectAt)
  external static T objectAt<T>(int address);

  /// Stops execution after a broken memory invariant; the heap cannot resume.
  @Primitive(.fail)
  external static Never fail();
}
