import 'contracts.dart';

/// Trusted machine capabilities; callers own bounds, alignment and lifetimes.
abstract final class Memory() {
  /// The active Dart execution context, preserved across native reentry.
  @Primitive(.context)
  external static int context();

  @Primitive(.writeByte)
  external static void writeByte(int address, int value);

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
