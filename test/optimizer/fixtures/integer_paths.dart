int guardedShift(int value) {
  if (value < 0) return 3;
  if (value >= 4) return 5;
  return (0 << (value * 8)) + 7;
}

int boundedLoop() {
  var bits = 0;
  for (var index = 0; index < 4; index++) {
    bits |= 0 << (index * 8);
  }
  return bits;
}

int checkedShift(int count) {
  try {
    return (0 << count) + 7;
  } on ArgumentError {
    return 13;
  }
}

int joinedBranches(int value) {
  final int next;
  if (value < 0) {
    next = value + 10;
  } else {
    next = value - 10;
  }
  return next < 0 ? -1 : 1;
}

int wrapping(int value) {
  if (value < 0x7fffffffffffffff) return 0;
  return value + 1 < 0 ? 1 : 2;
}

int unsignedShift(int value, int count) => value >>> count;
