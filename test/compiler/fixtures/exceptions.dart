import 'dart:ffi';

import 'package:dartc/interop.dart';

part 'exceptions_locations.dart';

class Token(final int value);

Never fail(Object value) => throw value;

void allocate(int count) {
  for (var i = 0; i < count; i++) {
    Token(i);
  }
}

@Export<Int64 Function(Int64, Int64, Pointer<Int64>)>()
int cleanup(int mode, int count, Pointer<Int64> effects) {
  final token = Token(7);
  try {
    try {
      effects.value = 1;
      if (mode == 0) return 100;
      fail(token);
    } catch (_) {
      effects.value = effects.value * 10 + 2;
      allocate(count);
      if (mode == 1) rethrow;
      if (mode == 2) return 200;
      throw token;
    } finally {
      effects.value = effects.value * 10 + 3;
      // ignore: control_flow_in_finally
      if (mode == 4) return 400;
      if (mode == 5) throw token;
    }
  } catch (_) {
    effects.value = effects.value * 10 + 4;
    return 307;
  } finally {
    effects.value = effects.value * 10 + 5;
  }
}

class FailingConstruction(int value, Pointer<Int64> effects) {
  this {
    effects.value += 1;
    fail(value);
  }
}

@Export<Int64 Function(Int64, Pointer<Int64>)>()
int constructorFailure(int value, Pointer<Int64> effects) {
  try {
    FailingConstruction(value, effects);
  } catch (_) {
    return effects.value;
  }
  return -1;
}

int recover(int value) {
  try {
    fail(value);
  } catch (_) {
    return value + 1;
  }
}

@Export<Int64 Function(Int64)>()
int recoveredCalls(int value) => recover(value) + recover(value + 1);

int choose(int value) {
  if (value < 0) throw value;
  return value * 2;
}

@Export<Int64 Function(Int64)>()
int checkedCall(int value) {
  try {
    return choose(value) + 1;
  } catch (_) {
    return -1;
  }
}

double chooseDouble(double value) {
  if (value < 0) throw value;
  return value + 0.25;
}

@Export<Double Function(Double)>()
double checkedDouble(double value) {
  try {
    return chooseDouble(value) * 2;
  } catch (_) {
    return -3.5;
  }
}

void main() => fail(7);

class TraceOverride() extends Error {
  static int reads = 0;
  @override
  StackTrace get stackTrace {
    reads++;
    return StackTrace.fromString('override');
  }

  StackTrace? get originalTrace => super.stackTrace;
}

class TraceInterface() implements Error {
  static int reads = 0;
  @override
  StackTrace? get stackTrace {
    reads++;
    return null;
  }
}

class TraceSource() {
  StackTrace capture() {
    StackTrace localTrace() => StackTrace.current;
    return localTrace();
  }
}

StackTrace namedTrace() => TraceSource().capture();

@Export<Bool Function(Int32)>()
bool stackTraceLifecycle(int mode) {
  if (mode == 7) return sourceLocations();
  if (mode == 6) {
    final trace = namedTrace();
    final text = trace.toString();
    allocate(40000);
    final local = text.indexOf('localTrace');
    final method = text.indexOf('TraceSource.capture', local + 1);
    final outer = text.indexOf('namedTrace', method + 1);
    return local >= 0 &&
        method > local &&
        outer > method &&
        trace.toString() == text;
  }
  if (mode == 0) {
    const text = 'user trace\n🦋\n';
    return StackTrace.empty.toString().isEmpty &&
        StackTrace.fromString(text).toString() == text;
  }
  if (mode == 1) {
    final trace = StackTrace.current;
    final text = trace.toString();
    allocate(40000);
    return text.isNotEmpty && trace.toString() == text;
  }
  if (mode == 4) {
    final error = TraceOverride();
    TraceOverride.reads = 0;
    try {
      throw error;
    } catch (_, trace) {
      return TraceOverride.reads == 0 &&
          error.originalTrace.toString() == trace.toString() &&
          error.stackTrace.toString() == 'override' &&
          TraceOverride.reads == 1;
    }
  }
  if (mode == 5) {
    TraceInterface.reads = 0;
    try {
      throw TraceInterface();
    } catch (error) {
      return TraceInterface.reads == 0 &&
          (error as Error).stackTrace == null &&
          TraceInterface.reads == 1;
    }
  }
  final error = StateError('first throw');
  if (error.stackTrace != null) return false;
  final supplied = StackTrace.fromString('supplied trace');
  StackTrace? first;
  try {
    if (mode == 3) Error.throwWithStackTrace(error, supplied);
    throw error;
  } catch (_, trace) {
    first = trace;
    if (mode == 3 && trace.toString() != supplied.toString()) return false;
    if (error.stackTrace.toString() != trace.toString()) return false;
  }
  allocate(40000);
  try {
    try {
      Error.throwWithStackTrace(error, StackTrace.fromString('second trace'));
    } catch (_) {
      rethrow;
    }
  } catch (_, trace) {
    return trace.toString() == 'second trace' &&
        error.stackTrace.toString() == first.toString();
  }
}

@Export<Int32 Function()>()
int traceDepth() => StackTrace.current.toString().split('\n').length;

@Export<Int32 Function(Pointer<NativeFunction<Int32 Function()>>)>()
int reenterTrace(Pointer<NativeFunction<Int32 Function()>> callback) =>
    callback.asFunction<int Function()>()();
