int previousWrite = 0;
Object? storedValue;

int storeScalar(int value) {
  previousWrite = 1;
  try {
    storedValue = value;
    previousWrite = 2;
    return 3;
  } catch (_) {
    return 100 + previousWrite;
  }
}

Object returnScalar(int value) {
  try {
    return value;
  } catch (_) {
    return 'allocation failed';
  }
}

String discardedView(int value) {
  value as Object;
  return 'ok';
}

Object? nullableJoin(bool condition, int value) {
  try {
    Object? result;
    if (condition) result = value;
    return result;
  } catch (_) {
    return 'allocation failed';
  }
}

bool scalarLocalTest(int value) {
  Object local = value;
  return local is int;
}

Type scalarViewRuntimeType(int value) => (value as Object).runtimeType;
