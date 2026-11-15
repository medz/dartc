class SubError() extends Error;

class OwnError() implements Error {
  @override
  StackTrace? get stackTrace => null;
}

class OwnArgumentError() implements ArgumentError {
  @override
  Object? get message => 'custom';
  @override
  Object? get invalidValue => null;
  @override
  String? get name => null;
  @override
  StackTrace? get stackTrace => null;
}

class GetterError() extends Error {
  @override
  StackTrace? get stackTrace => StackTrace.empty;
  StackTrace? get recorded => super.stackTrace;
}

class Plain();

Object makeSub() => SubError();
Object makeOwn() => OwnError();
Object makeArgument() => OwnArgumentError();
Object makeGetter() => GetterError();
Object makePlain() => Plain();
StackTrace? readTrace(Object error) => (error as Error).stackTrace;
StackTrace? readStored(Object error) => (error as GetterError).recorded;

StackTrace? repeatTrace(StackTrace first, StackTrace second) {
  final error = SubError();
  try {
    try {
      Error.throwWithStackTrace(error, first);
    } catch (_) {
      rethrow;
    }
  } catch (_) {}
  try {
    Error.throwWithStackTrace(error, second);
  } catch (_) {}
  return error.stackTrace;
}

int ignoredError(int value) {
  try {
    try {
      throw SubError();
    } finally {
      value += 1;
    }
  } catch (_) {
    return value;
  }
}

StackTrace observedTrace() {
  try {
    throw SubError();
  } catch (_, trace) {
    return trace;
  }
}
