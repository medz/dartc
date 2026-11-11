import 'dart:ffi';

/// Chooses a semispace capacity, or zero if the requested size cannot fit.
int heapCapacity(int current, int needed) {
  const maximum = 0x2000000000000000;
  const halfMaximum = maximum ~/ 2;
  if (current < 0 || current > maximum || needed < 0 || needed > maximum) {
    return 0;
  }
  var capacity = current == 0 ? 65536 : current;
  while (capacity < needed) {
    if (capacity > halfMaximum) return maximum;
    capacity *= 2;
  }
  return capacity;
}

/// Copies [words] aligned words between valid, nonoverlapping memory regions.
void copyWords(Pointer<Int64> destination, Pointer<Int64> source, int words) {
  for (var i = 0; i < words; i++) {
    destination[i] = source[i];
  }
}

/// Clears [words] aligned words in writable native memory.
void clearWords(Pointer<Int64> destination, int words) {
  for (var i = 0; i < words; i++) {
    destination[i] = 0;
  }
}
