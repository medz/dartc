/// Trusted machine capabilities; callers own bounds, alignment and lifetimes.
abstract final class Memory() {
  /// Reserves zero-filled pages, or returns zero on exhaustion.
  external static int map(int bytes);

  /// Releases a region returned by [map].
  external static void unmap(int address, int bytes);

  /// Reads one aligned machine word from live storage.
  external static int read(int address);

  /// Writes one aligned machine word to live storage.
  external static void write(int address, int value);

  /// Observes an object's address while moving collection is suspended.
  external static int addressOf(Object? value);

  /// Recovers an existing object whose initialized storage has type [T].
  external static T objectAt<T>(int address);

  /// Stops execution after a broken memory invariant; the heap cannot resume.
  external static Never fail();
}
