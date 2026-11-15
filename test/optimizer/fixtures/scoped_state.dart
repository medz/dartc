int current = 7;

int work(int value) {
  if (value < 0) throw value;
  return value + 1;
}

int observe(int value) => work(value) + current;

void replace() {
  current = 19;
}

int restored(int value) {
  final saved = current;
  current = value;
  try {
    return work(value);
  } finally {
    current = saved;
  }
}

int observed(int value) {
  final saved = current;
  current = value;
  try {
    return observe(value);
  } finally {
    current = saved;
  }
}

int incomplete(int value) {
  final saved = current;
  current = value;
  try {
    return work(value);
  } finally {
    if (value >= 0) current = saved;
  }
}

int overwritten(int value) {
  final saved = current;
  current = value;
  current = saved;
  replace();
  current = saved;
  return current;
}

int exercise(int Function(int) callback, int value) {
  current = 7;
  int result;
  try {
    result = callback(value);
  } on int catch (error) {
    result = error;
  }
  return result + current;
}

int restoreResult(int value) => exercise(restored, value);
int observeResult(int value) => exercise(observed, value);
int incompleteResult(int value) => exercise(incomplete, value);
int overwrittenResult(int value) => exercise(overwritten, value);
