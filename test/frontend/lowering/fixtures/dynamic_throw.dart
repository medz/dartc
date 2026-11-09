import 'effects.dart';

Object? direct(dynamic value) => throw value;

dynamic operand(dynamic value) {
  tick(1);
  return value;
}

Object? withFinally(dynamic value) {
  try {
    throw operand(value);
  } finally {
    tick(2);
  }
}

int caught(dynamic value) {
  try {
    throw operand(value);
  } on TypeError {
    tick(3);
    return 30;
  } catch (error) {
    tick(4);
    return identical(error, value) ? 40 : 41;
  } finally {
    tick(5);
  }
}

int rethrowIdentity(dynamic value) {
  Object? original;
  StackTrace? originalTrace;
  try {
    try {
      throw operand(value);
    } catch (error, trace) {
      original = error;
      originalTrace = trace;
      tick(2);
      rethrow;
    } finally {
      tick(3);
    }
  } catch (error, trace) {
    tick(4);
    return (identical(error, original) ? 1 : 0) +
        (identical(trace, originalTrace) ? 2 : 0) +
        (identical(error, value) ? 4 : 0) +
        (error is TypeError ? 8 : 0);
  } finally {
    tick(5);
  }
}

int operandFailure(dynamic value) {
  try {
    throw (tick(-1) == 0 ? value : operand(value));
  } on StateError {
    tick(2);
    return 20;
  } on TypeError {
    return 30;
  } finally {
    tick(4);
  }
}

Object? finallyOverrides(dynamic value) {
  try {
    throw operand(value);
  } finally {
    tick(2);
    throw 99;
  }
}
