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
