int straight(int input) {
  int result;
  result = input + 1;
  return result;
}

int wildcardBindings(int _) {
  var count = 0;
  var _ = count++;
  final _ = count += 2;
  final (_, _) = (count++, count++);
  return count;
}

int wildcardThrow() {
  var count = 0;
  try {
    var _ = count++, _ = throw 7;
    // ignore: dead_code
    count = 20;
  } catch (_) {
    count += 3;
  }
  return count;
}

int branches(bool first, int input) {
  final int result;
  if (first) {
    result = input + 1;
  } else {
    result = input - 1;
  }
  return result;
}

int nestedBranches(bool first, bool second) {
  int result;
  if (first) {
    if (second) {
      result = 11;
    } else {
      result = 12;
    }
  } else {
    result = 13;
  }
  result += 20;
  return result;
}

int? nullableFinal(bool first) {
  final int? result;
  if (first) {
    result = 7;
  } else {
    result = null;
  }
  return result;
}

int nullableDefault() {
  int? result;
  return result ?? 9;
}

int returningBranch(bool first) {
  final int result;
  if (first) return 10;
  result = 20;
  return result;
}

int loopAssignment(int count) {
  int result;
  do {
    result = count;
    count--;
  } while (count > 0);
  return result;
}

int breakAssignment(int input) {
  int result;
  while (true) {
    result = input;
    break;
  }
  return result;
}

int switchAssignment(int input) {
  final int result;
  switch (input) {
    case 0:
      result = 10;
    case 1:
      result = 11;
    default:
      result = 12;
  }
  return result;
}

int capturedFinal(bool first) {
  final int result;
  if (first) {
    result = 17;
  } else {
    result = 18;
  }
  int read() => result;
  return read();
}

int capturedMutable(int input) {
  int result;
  result = input;
  int read() => result;
  result += 3;
  return read();
}

int capturedBeforeAssignment(int input) {
  int result;
  void write() {
    result = input;
  }

  write();
  // Dart cannot establish assignment through the call, so assign again.
  result = input + 1;
  return result;
}

int catchAssignment(bool fail) {
  int result;
  try {
    if (fail) throw 1;
    result = 30;
  } catch (_) {
    result = 31;
  }
  return result;
}

int finallyAssignment(int input) {
  int result;
  try {
    result = input;
  } finally {
    result = input + 2;
  }
  return result;
}

int shadowAssignment(int input) {
  final int result;
  {
    final int result;
    result = input + 1;
    input = result;
  }
  result = input + 2;
  return result;
}

int unusedForBinding(int count) {
  int total = 0;
  for (int value; count > 0; count--) {
    if (count == 2) {
      value = count;
      total += value;
    }
  }
  return total;
}

int initializedForBinding(int count) {
  int total = 0;
  for (int value; count > 0; count--) {
    value = count;
    total += value;
  }
  return total;
}

int capturedUninitializedForBinding(int count) {
  int Function()? callback;
  for (int value; count > 0; count--) {
    int initialize() {
      value = 42;
      return value;
    }

    callback = initialize;
  }
  return callback?.call() ?? 0;
}
