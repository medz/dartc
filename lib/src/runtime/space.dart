import 'memory.dart';

/// A semispace and its allocation and Cheney scan cursors.
final class Space() {
  int start = 0;
  int capacity = 0;
  int used = 0;
  int scanned = 0;

  bool contains(int address) => address >= start && address - start < used;

  /// Returns zero without changing the space when [bytes] cannot fit.
  int reserve(int bytes) {
    if (bytes < 0 || bytes > capacity - used) return 0;
    final address = start + used;
    used += bytes;
    return address;
  }

  void reset() {
    used = 0;
    scanned = 0;
  }

  void close() {
    if (start != 0) Memory.unmap(start, capacity);
    start = 0;
    capacity = 0;
    reset();
  }
}

/// Chooses a semispace capacity without overflowing the allocation limit.
int heapCapacity(int current, int needed) {
  const maximum = 0x2000000000000000;
  if (current < 0 || current > maximum || needed < 0 || needed > maximum) {
    return 0;
  }
  var capacity = current == 0 ? 65536 : current;
  while (capacity < needed) {
    if (capacity > maximum >> 1) return maximum;
    capacity *= 2;
  }
  return capacity;
}
