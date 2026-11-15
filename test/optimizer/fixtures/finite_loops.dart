import '../../frontend/lowering/fixtures/effects.dart' as effects;

int digits() {
  var result = 0;
  for (var index = 0; index < 4; index++) {
    result = result * 10 + index;
  }
  return result;
}

int countdown() {
  var count = 4, result = 0;
  while (count != 0) {
    count--;
    result = result * 10 + count;
  }
  return result;
}

int stepped() {
  var result = 0;
  for (var index = 1; index <= 5; index += 2) {
    result = result * 10 + index;
  }
  return result;
}

int descending() {
  var result = 0;
  for (var index = 4; index >= -2; index -= 2) {
    result = result * 10 + index;
  }
  return result;
}

int reversed() {
  var result = 0;
  for (var index = 0; 4 > index; index++) {
    result = result * 10 + index;
  }
  return result;
}

int once() {
  var result = 0;
  for (var index = 2; index == 2; index++) {
    result += index;
  }
  return result;
}

int nested() {
  var result = 0;
  for (var row = 0; row < 2; row++) {
    for (var column = 0; column < 2; column++) {
      result = result * 10 + row + column;
    }
  }
  return result;
}

int continuationLoop(int input) {
  var digits = 0;
  for (var index = 0; index < 4; index++) {
    digits = digits * 10 + index;
  }
  var count = input & 3, result = digits;
  while (count > 0) {
    result += digits;
    count--;
  }
  return result;
}

class Box(final int value);

int objects() {
  var result = 0;
  for (var index = 0; index < 4; index++) {
    final box = Box(index);
    result = result * 10 + box.value;
  }
  return result;
}

int runtimeCount(int count) {
  var result = 0;
  for (var index = 0; index < count; index++) {
    result = result * 10 + index;
  }
  return result;
}

int earlyExit(int stop) {
  var result = 0;
  for (var index = 0; index < 4; index++) {
    effects.tick(index);
    try {
      if (index == stop) throw index + 10;
      if (-index - 1 == stop) break;
      result = result * 10 + index;
    } on int catch (error) {
      return result + error;
    } finally {
      effects.tick(index + 100);
    }
  }
  return result;
}

int wrapping(int stop) {
  var result = 0;
  for (var index = 0x7fffffffffffffff; index <= 0x7fffffffffffffff; index++) {
    if (index == stop) return result;
    result++;
  }
  return result;
}

int missingStop() {
  var result = 0;
  for (var index = 0; index != 3; index += 2) {
    result += index;
  }
  return result;
}

int nearLimit() {
  var result = 0;
  for (var index = 0x7ffffffffffffffc; index < 0x7fffffffffffffff; index++) {
    result += index;
  }
  return result;
}

int lowerLimit() {
  var result = 0;
  for (var index = -0x7ffffffffffffffd; index > -0x8000000000000000; index--) {
    result += index;
  }
  return result;
}

int changingLimit() {
  var limit = 3, result = 0;
  for (var index = 0; index < limit; index++) {
    if (index == 1) limit = 7;
    result++;
  }
  return result;
}

int continued(int skip) {
  var result = 0;
  for (var index = 0; index < 4; index++) {
    if (index == skip) continue;
    result = result * 10 + index;
  }
  return result;
}

int outerCatch(int fail) {
  var result = 3;
  try {
    if (fail < 0) throw 17;
    for (var index = 0; index < 4; index++) {
      result = result * 10 + index;
      if (index == fail) throw 19;
    }
  } on int catch (error) {
    return result + error;
  }
  return result;
}
