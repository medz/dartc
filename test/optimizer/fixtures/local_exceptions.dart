final class Payload(final int value);

int caughtValue(int value) {
  try {
    throw value;
  } on int catch (error) {
    return error + 2;
  }
}

int caughtObject(int value) {
  try {
    throw Payload(value);
  } on Payload catch (error) {
    return error.value + 2;
  }
}

int ignoredObject(int value) {
  try {
    throw Payload(value);
  } on Payload {
    return value + 2;
  }
}

int caughtRethrow(int value) {
  try {
    try {
      throw Payload(value);
    } on Payload {
      rethrow;
    }
  } on Payload catch (error) {
    return error.value + 2;
  }
}

int caughtFinally(int value) {
  var observed = value;
  try {
    try {
      throw Payload(value + 1);
    } finally {
      observed += 3;
    }
  } on Payload catch (error) {
    return observed + error.value;
  }
}

int mixedErrorTrace(bool useOrdinary) {
  final error = useOrdinary ? Error() : const OutOfMemoryError();
  try {
    Error.throwWithStackTrace(error, StackTrace.empty);
  } on OutOfMemoryError catch (e, s) {
    return identical(e, const OutOfMemoryError()) &&
            identical(s, StackTrace.empty) &&
            e.stackTrace == null
        ? 1
        : -1;
  } on Error catch (e, s) {
    return identical(e, error) && identical(e.stackTrace, s) ? 2 : -2;
  }
}
